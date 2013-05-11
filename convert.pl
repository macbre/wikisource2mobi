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

use Encode qw(decode);

# HTTP utils
use constant USER_AGENT => "Mozilla/5.0 (wikisource2mobi)";

sub getUrl($) {
	(my $url) = @_;

	my $ua = new LWP::UserAgent;
	$ua->agent(USER_AGENT);

	my $req = new HTTP::Request 'GET' => $url;
	my $res = $ua->request($req) or die "HTTP request failed!";
	my $html = $res->{_content};

	# @see http://stackoverflow.com/questions/4572007/perl-lwpuseragent-mishandling-utf-8-response
	return Encode::decode("utf8", $html);
}

# validate CLI arguments
die "Please pass book YAML file" unless defined $ARGV[0];
die "YAML file doesn't exist" unless -e $ARGV[0];

my $bookInfoFile = $ARGV[0];
my $workDir = dirname(realpath($bookInfoFile));

say "Using $bookInfoFile (working in $workDir directory)...";

# parse desc file
my $yaml = YAML::Tiny->read($bookInfoFile) or die "Cannot open YAML file";
$yaml = $yaml->[0];

#say Dumper($yaml);

# prepare the book
my $book = EBook::MOBI->new();
my $converter = EBook::MOBI::Converter->new();

$book->set_filename("$workDir/book.mobi");
$book->set_title   ($yaml->{title});
$book->set_author  ($yaml->{author});

# generate cover
$book->add_mhtml_content("<center><h1>$yaml->{title}</h1><h2>$yaml->{author}</h2></center>");
$book->add_pagebreak();

# TOC
$book->add_toc_once("Spis treści");
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

say "\nFound " . scalar(@chapters) . " chapters";

#say Dumper(@chapters);

# fetch chapters
foreach my $chapter (@chapters) {
	my $url = "http://pl.wikisource.org/w/index.php?title=" . $chapter . "&action=render";
	say "Fetching <$url>...";

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
			$book->add_mhtml_content( $converter->title($_) . "<br><br>" ); # add a chapter name
		}
		else {
			$book->add_mhtml_content( $converter->paragraph($_) ); # add a paragraph
		}
	}

	$book->add_pagebreak();
}

# now generate an ebook
say "Writing MOBI file...";
$book->make();

# generate HTML file with the content
open my $html, '>:utf8', "$workDir/content.html" or die "Cannot create HTML file";

print $html $book->print_mhtml(1);
close $html;

# save the file
$book->save() or die "save() failed";

say "\nDone!";
