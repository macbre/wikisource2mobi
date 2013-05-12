#!/usr/bin/env perl
use common::sense;
use LWP::UserAgent;
use URI::Escape;
use HTML::TreeBuilder::XPath;
use YAML::Tiny;
use Data::Dumper;
use Cwd 'realpath';
use File::Basename 'dirname';
use EBook::MOBI;
use Encode;

# HTTP utils
use constant USER_AGENT => "Mozilla/5.0 (wikisource2mobi)";

sub getUrl($) {
	(my $url) = @_;

	my $ua = new LWP::UserAgent;
	$ua->agent(USER_AGENT);

	my $req = new HTTP::Request 'GET' => $url;
	my $res = $ua->request($req) or die "HTTP request failed!";
	my $html = $res->{_content};

	return $html;
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

#say Dumper($yaml);

say "My workplace will be in $workDir...";

# prepare the book
my $book = EBook::MOBI->new();
my $converter = EBook::MOBI::Converter->new();

$book->set_filename("$workDir/book.mobi");
$book->set_title   (Encode::encode('utf8', $yaml->{title}));
$book->set_author  (Encode::encode('utf8', $yaml->{author}));

# generate cover
$book->add_mhtml_content("<h1>" . Encode::encode('utf8', $yaml->{title}) . "</h1>");
$book->add_mhtml_content("<h2>" . Encode::encode('utf8', $yaml->{author}) . "</h2>");
$book->add_pagebreak();

# TOC
$book->add_toc_once(Encode::encode('utf8', "Spis treści"));
$book->add_pagebreak();

# fetch the index file
my $source = $yaml->{source} . "?action=raw";
say "\nFetching $source...";

my $index = getUrl($source) or die "Cannot fetch the index";

#say Dumper($index);

# parse the index to get chapters
my @lines = split(/\n/, $index);
my @chapters;

foreach (@lines) {
	next unless /^\*\s?\[\[/;
	chomp;

	s/^\*\s?|\[\[|\]\]//g; # clean wikitext - remove brackets and bullet points
	s/\|(.*)$//; # [[Cień (Grabiński)|Cień]] -> Cień (Grabiński)

	s/ /\_/g; # wiki-encode spaces

	push @chapters, $_;
}

say "\nFound " . scalar(@chapters) . " chapters:";

#say Dumper(@chapters);

# fetch chapters
foreach my $chapter (@chapters) {
	my $url = "http://pl.wikisource.org/w/index.php?title=" . $chapter . "&action=render";
	say "* fetching <$url>...";

	my $html = getUrl($url) or die "Cannot fetch the chapter";
	$html =~ s/<br \/>|&#160;/<\/p><p>/g;

	my $tree= HTML::TreeBuilder::XPath->new;
	$tree->parse($html) or die "Cannot parse chapter's HTML";

	my @nodes = $tree->findnodes_as_strings(q{//body/table//p});
	my $line;

	foreach(@nodes) {
		s/\[\d+\]//g; # remove references
		next if /^\s?$/; # skip empty lines

		$line++;

		if ($line eq 1) {
			$book->add_mhtml_content( $converter->title($_) ); # add a chapter name
			$book->add_mhtml_content( $converter->paragraph("<br /><br />") );
		}
		else {
			$book->add_mhtml_content( $converter->paragraph($_) ); # add a paragraph
		}
	}

	$book->add_pagebreak();
}

# copyright stuff
my $date = `date +%d\\ %B\\ %Y`;
$book->add_mhtml_content(Encode::encode('utf8', <<COPYRIGHT
<p><center><small>
	<br /><br />
	<br /><br />
	<br /><br />
	Przygotowanie oraz konwersja do formatu MOBI:
	<br />
	Maciej Brencz <maciej.brencz\@gmail.com>
	<br /><br />
	Źródło:
	<br />
	WikiŹródła, zasób udostępniony na zasadach Domeny Publicznej
	<br>
	<a href="$yaml->{source}">$yaml->{source}</a>
	<br /><br />
	Data wygenerowania pliku:
	<br>
	$date
	<br /><br />
	Generowanie plików MOBI napędza <a href="https://github.com/macbre/wikisource2mobi">wikisource2mobi</a>
	<br /><br />
	<strong>Miłej lektury!</strong>
</small></center></p>
COPYRIGHT
));

# now generate an ebook
say "\nWriting MOBI file...";
$book->make();

# generate HTML file with the content
open my $html, '>:utf8', "$workDir/content.html" or die "Cannot create HTML file";

print $html $book->print_mhtml(1);
close $html;

# save the file
$book->save() or die "save() failed";

say "Done!";
