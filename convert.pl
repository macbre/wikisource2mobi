#!/usr/bin/env perl
use common::sense;
use LWP::UserAgent;
use HTML::TreeBuilder::XPath;
use HTML::TreeBuilder::LibXML;
use YAML::Tiny;
use Text::Iconv;
use Data::Dumper;
use Cwd 'realpath';
use File::Basename 'dirname';
use EBook::EPUB;
use Encode;
use File::Temp 'tempfile';

# HTTP utils
use constant {
	VERSION    => "0.1.1",
	USER_AGENT => "Mozilla/5.0 (wikisource2mobi)"
};

say "wikisource2mobi v" . VERSION;

sub getUrl($;$) {
	my ($url, $encoding) = @_;

	my $ua = new LWP::UserAgent;
	$ua->agent(USER_AGENT);

	my $req = new HTTP::Request 'GET' => $url;
	my $res = $ua->request($req) or die "HTTP request failed!";
	my $html = $res->{_content};

	# convert encodings
	if (defined $encoding) {
		my $converter = Text::Iconv->new($encoding, 'utf8');
		$html = $converter->convert($html);
	}

	return $html;
}

sub storeInTemp($;$) {
	my ($content, $binmode) = @_;
	my ($fp, $file) = tempfile('epub_XXXX', TMPDIR => 1) or die "Cannot create temporary file";

	binmode $fp, $binmode if defined $binmode;
	print $fp $content;
	close $fp;

	return $file;
}

# chapters generation
my $chaptersCnt;
sub addChapter($$$) {
	my ($epub, $title, $html) = @_;

	say "Adding a chapter \"" . Encode::encode('utf8', $title) . "\"...";

	# wrap HTML into xHTML document
	$html = <<HTML
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<title>$title</title>
</head>
<body>
$html
</body>
</html>
HTML
;

	# write to a temporary file
	my $file = storeInTemp($html, ':utf8');

	# add to the TOC
	$chaptersCnt++;
	my $name = "chapter$chaptersCnt.xhtml";
	my $chapter_id = $epub->copy_xhtml($file, $name);

	$epub->add_navpoint(
		label       => $title,
		id          => $chapter_id,
		content     => $name,
		play_order  => $chaptersCnt
	);
}

# validate CLI arguments
die "Please pass book YAML file" unless defined $ARGV[0];
die "YAML file doesn't exist" unless -e $ARGV[0];

my $bookInfoFile = $ARGV[0];
my $workDir = dirname(realpath($bookInfoFile));

say "Loading $bookInfoFile info file...";

# parse desc file
my $yaml = YAML::Tiny->read($bookInfoFile) or die "Cannot open YAML file";
$yaml = $yaml->[0];

#say Dumper($yaml); exit;

say "My workplace will be in <$workDir>\n";

# prepare the book
my $epub = EBook::EPUB->new;

$epub->add_title($yaml->{title});
$epub->add_author($yaml->{author});
$epub->add_language('pl');
$epub->add_publisher('wikisource2mobi');
$epub->add_source($yaml->{source});

$epub->add_identifier($yaml->{isbn}, 'ISBN') if exists $yaml->{isbn};

# add CSS
$epub->copy_stylesheet(realpath('./css/base.css'), 'style.css');

my @chapters;

if (exists $yaml->{chapters}) {
	@chapters = @{$yaml->{chapters}};
}
# fetch the index file (if chapters not provided)
elsif (exists $yaml->{source}) {
	my $source = $yaml->{source} . "?action=raw";
	say "Fetching and parsing <$source>...";

	my $index = getUrl($source, $yaml->{encoding}) or die "Cannot fetch the index";

	# parse the index to get chapters
	my @lines = split(/\n/, $index);

	foreach (@lines) {
		# * [[Cień (Grabiński)|Cień]]
		# [[Biały Wyrak]]<br>
		# [[Przed drogą daleką]] (Urywki z pamiętnika W. Lasoty)<br>
		next unless /^\*\s?\[\[|\[\[[^\:]+\]\](.*)?<br>/;
		chomp;

		s/\]\](.*)$//; # [[Przed drogą daleką]] (Urywki z pamiętnika W. Lasoty)<br> -> [[Przed drogą daleką]]
		s/^\*\s?|\[\[|\]\]|<br>//g; # clean wikitext - remove brackets and bullet points
		s/\|(.*)$//; # [[Cień (Grabiński)|Cień]] -> Cień (Grabiński)

		s/ /\_/g; # wiki-encode spaces

		push @chapters, "http://pl.wikisource.org/w/index.php?title=$_&action=render";
	}

	say "\nFound " . scalar(@chapters) . " chapters:";
}
else {
	die "Nor index nor source defined in YAML";
}

#say Dumper(@chapters); exit;

# cover (text version)
addChapter($epub, "Okładka", <<COVER
	<p><br /><br /></p>
	<h1><center>$yaml->{title}</center></h1>
	<h2><center>$yaml->{author}</center></h2>
COVER
);

# cover (an image)
# Add cover image
# Not actual epub standart but does the trick for iBooks
if (exists $yaml->{cover}) {
	use File::Temp qw/ :POSIX /;
	say "Fetching a cover from <$yaml->{cover}>...\n";

	my $cover = getUrl($yaml->{cover}) or die "Cannot fetch a cover";
	my $file = storeInTemp($cover);

	my $cover_id = $epub->copy_image($file, 'cover.jpg');
	$epub->add_meta_item('cover', $cover_id);
}

# fetch chapters
foreach my $url (@chapters) {
	say "* fetching and parsing <$url>...";

	my $html = getUrl($url, $yaml->{encoding}) or die "Cannot fetch the chapter";

	# proper UTF handling
	$html = Encode::decode('utf8', $html);

	# clean HTML
	$html =~ s/<br \/>|&#160;/<\/p><p>/g;
	$html =~ s/&nbsp;/ /g;

	my $tree= HTML::TreeBuilder::LibXML->new;
	$tree->parse($html) or die "Cannot parse chapter's HTML";

	# xpath magic
	my $contentXPath = $yaml->{xpath}->{content} // q{//body/*[not(@id="mojNaglowek") and not(@id="Template_law")]//p[not(big)]};
	my $headerXPath = $yaml->{xpath}->{header} // q{//body//div[@id="mojNaglowek"]//td/b};

	# chapter title
	my @nodes = $tree->findnodes_as_strings($headerXPath) or die("No header nodes found");
	my $chapterTitle = pop @nodes;

	my $content;
	$content .= "<p><br /><br /></p>\n";
	$content .= "<h1>$chapterTitle</h1>\n";
	$content .= "<p><br /><br /></p>\n";

	# content
	my @nodes = $tree->findnodes($contentXPath) or die("No content nodes found");

	foreach my $node (@nodes) {
		my $isHeading = $node->tag() =~ /h\d/; # is h1, h2, ...?
		my $isCode = $node->tag() =~ /pre|code|textarea/;
		my $text = $node->as_text;

		$text =~ s/\[\d+\]//g; # remove references
		next if $text =~ /^\s?$/; # skip empty lines

		$text =~ s/^\s+|\s+$//g; # remove whitespaces
		$text =~ s/&/&amp;/g; # encode HTML entities
		$text =~ s/</&lt;/g; # encode HTML entities
		$text =~ s/>/&gt;/g; # encode HTML entities

		if ($isCode) {
			$content .= "<pre>$text</pre>";
		}
		elsif ($isHeading) {
			$content .= "<h3>$text</h3>";
		}
		else {
			$content .= "<p>$text</p>\n";
		}
	}

	$tree->delete; # to avoid memory leaks

	addChapter($epub, $chapterTitle, $content);
}

# copyright stuff
my $date = `date +%d\\ %B\\ %Y`;
addChapter($epub, "Nota redakcyjna", <<COPYRIGHT
<p><center><small>
	<br /><br />
	<br /><br />
	<br /><br />
	Przygotowanie oraz konwersja do formatów EPUB i MOBI:
	<br />
	Maciej Brencz &lt;maciej.brencz\@gmail.com&gt;
	<br /><br />
	Źródło:
	<br />
	Zasób udostępniony na zasadach Domeny Publicznej
	<br />
	<a href="$yaml->{source}">$yaml->{source}</a>
	<br /><br />
	Data wydania oryginału:
	<br />
	$yaml->{pubdate} r.
	<br /><br />
	Data wygenerowania pliku:
	<br />
	$date r.
	<br /><br />
	Generowanie plików EPUB oraz MOBI napędza <a href="https://github.com/macbre/wikisource2mobi">wikisource2mobi</a> v@{[VERSION]}
	<br /><br />
	<strong>Miłej lektury!</strong>
</small></center></p>
COPYRIGHT
);

# now generate an ebook
say "\nWriting EPUB file...";
$epub->pack_zip("$workDir/book.epub");

# convert to mobi as well
# @see http://manual.calibre-ebook.com/cli/ebook-convert.html
say "Generating MOBI file from EPUB...";
system("/usr/bin/env ebook-convert $workDir/book.epub $workDir/book.mobi > /dev/null") == 0 or say("Conversion failed");

say "Done!";

