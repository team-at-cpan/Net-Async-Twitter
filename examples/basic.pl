#!/usr/bin/env perl 
use strict;
use warnings;
use 5.010;

use IO::Async::Loop;
use Net::Async::HTTP;
use Net::Async::Twitter;
use JSON::MaybeXS;
use Data::Dumper;

my $loop = IO::Async::Loop->new;
$loop->add(my $ua = Net::Async::HTTP->new);

my $t = Net::Async::Twitter->new(
    consumer_key    => '3MgnQVxdJWEmV619LNIqH8KP7',
    consumer_secret => '24EjkWsoF58ukP17O81BrCpvCzUHfUULHDFtQlYQLVeIKTWeJc',
    token_secret    => 'RkTY8pBqKW0mxNhbPFX8U4ubgcgFYOGMDA2Dkae3TSw',
	token           => '185682166-Yut6HOs3BJ7DXgcOGhqeoBFvATows1GUDhdRO5J4',
);

my $uri = URI->new('https://stream.twitter.com/1.1/statuses/sample.json');
my $req = HTTP::Request->new(GET => "$uri");
$req->protocol('HTTP/1.1');
# $req->header(Authorization => 'Bearer ' . $t->req);
my $hdr = $t->authorization_header(
	method => 'GET',
	url => "$uri",
	parameters => { $uri->query_form },
);
$req->header('Authorization' => $hdr);
say "Had auth header: $hdr";
$req->header('Host' => $uri->host);
$req->header('User-Agent' => 'OAuth gem v0.4.4');
$req->header('Connection' => 'close');
$req->header('Accept' => '*/*');

say $req->as_string("\n");
binmode STDOUT, ':encoding(UTF-8)';

$ua->do_request(
	request => $req,
	on_header => sub {
		my $hdr = shift;
		say "Header: $hdr";
        my $json = JSON::MaybeXS->new;
		sub {
			return unless @_;
			my $data = shift;
            my @found = $json->incr_parse($data);
            for(@found) {
                next unless exists $_->{text};
                say Dumper($_) unless defined $_->{text};
                say $_->{user}{screen_name} . ': ' . $_->{text};
            }
		}
	}
);
$loop->run;

