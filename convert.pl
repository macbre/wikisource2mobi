#!/usr/bin/env perl
use common::sense;
use LWP::UserAgent;
use URI::Escape;
use HTML::TreeBuilder::XPath;
use YAML::Tiny;
use Data::Dumper;
use Cwd 'realpath';
use File::Basename 'dirname';

# HTTP utils
use constant USER_AGENT => "Mozilla/5.0 (wikisource2mobi)";

sub getUrl($) {
	(my $url) = @_;

	my $ua = new LWP::UserAgent;
	$ua->agent(USER_AGENT);

	my $req = new HTTP::Request 'GET' => $url;
	my $res = $ua->request($req);

	return $res->{_content} or die "Request failed";
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

	foreach(@nodes) {
		next if /^\s?$/; # skip empty lines
		s/\[\d+\]//g; # remove references

		say;
	}
}

say "\nDone!";
