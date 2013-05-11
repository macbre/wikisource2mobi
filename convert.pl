#!/usr/bin/env perl
use common::sense;
use LWP::UserAgent;
use URI::Escape;
use YAML::Tiny;
use Data::Dumper;
use Cwd 'realpath';
use File::Basename 'dirname';

# pretend we're a fancy browser
use constant USER_AGENT => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.31 (KHTML, like Gecko) Chrome/26.0.1410.63 Safari/537.31";

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
	my $url = "http://pl.wikisource.org/w/index.php?title=" . uri_escape_utf8($chapter) . "&action=render";
	say "Fetching <$url>...";

	my $content = getUrl($url); # or die "Cannot fetch the chapter";

	#say Dumper($content);
}

say "\nDone!";
