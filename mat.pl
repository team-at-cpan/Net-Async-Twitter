#!/usr/bin/env perl 
use strict;
use warnings;
use feature qw(say);
use JSON::MaybeXS;
use IO::Async::Loop;
use Net::Async::Matrix;
use Net::Async::Twitter;
use Net::Async::HTTP;
use URI::Escape qw(uri_escape_utf8);
use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use MIME::Types;

my $loop = IO::Async::Loop->new;
my $t = Net::Async::Twitter->new(
    consumer_key    => '3XUUQDUrex9C7XtKKX38fqrST',
    consumer_secret => '4YeKf2E0zfcNOBOuTTVP3x6kLjFdj7WksoqyORfFqpIYuEsgsO',
    token_secret    => 'cRrfRqGeUC0SHE4jPqm4EaQxHLWfJBNuL1BeIGkGIBDeW',
	token           => '2789773224-fUzpvN5b45fyky3PNpyvUInZGS2HeTrR1twyO6v',
);

$loop->add(
	my $ua = Net::Async::HTTP->new(
		max_connections_per_host => 0,
		pipeline                 => 0,
		fail_on_error            => 1,
	)
);

sub twatpic {
	my ($uri, $user) = @_;
	$uri = URI->new($uri) unless ref $uri;

	my $enable;
	my @pending;
	my $done;
	my $write = sub {
		$enable->() if $enable;
		if(@_) {
			my $data = shift;
			warn "Queuing " . length($data) . " bytes\n";
			push @pending, sprintf("%04x\x0D\x0A", length $data) . $data . "\x0D\x0A";
		} else {
			$done = 1;
			warn "Writer finished\n";
			push @pending, sprintf("%04x\x0D\x0A", 0) . "\x0D\x0A";
		}
		1
	};

	# so we read from the source...
	my $poster;
	$ua->GET(
		$uri,
		SSL_verify_mode => SSL_VERIFY_NONE,
		on_header => sub {
			my ($resp) = @_;
			my $mime = $resp->header('Content-Type');
			my $types = MIME::Types->new;
			my ($ext) = $types->type($mime)->extensions;
			# meh
			$ext = 'jpg' if $ext eq 'jpeg';
			warn "Data retrieved with $ext as extension\n";

			my $sep = 'cce6735153bf14e47e999e68bb183e70a1fa7fc89722fc1efdf03a917340';
			# Generate our Twitter request, no parameters since we have multipart streaming data
			my $post_uri = URI->new('https://api.twitter.com/1.1/statuses/update_with_media.json');
			my $req = HTTP::Request->new(POST => $post_uri, [
				'Transfer-Encoding' => 'chunked',
				'Content-Type' => "multipart/form-data;boundary=$sep",
			]);
			$req->protocol('HTTP/1.1');
			my $hdr = $t->authorization_header(
				method     => 'POST',
				uri        => $post_uri,
				parameters => { }
			);
			$req->header('Authorization' => $hdr);
			$req->header('Host' => $post_uri->host);
			$req->header('User-Agent' => 'OAuth gem v0.4.4');
			$req->header('Accept' => '*/*');
			warn $req->as_string("\n");

			# Initiate the POST request to Twitter
			$poster = $ua->do_request(
				request => $req,
				request_body => sub {
					my ($stream) = @_;
					if(@pending) {
						# don't spam want_writeready
						undef $enable;
						warn "Body request - had " . @pending . " in queue\n";
						return shift @pending;
					}
					warn "Request body done\n" if $done;
					return undef if $done;
					$enable = sub {
						warn "Enabling stream\n";
						$stream->want_writeready(1);
					};
					warn "Disabling stream\n";
					$stream->want_writeready(0);
					return '';
				}
			);
			$write->(map s/\n/\x0D\x0A/gr, <<"EOF");
--$sep
Content-Disposition: form-data; name="status"

$user posted an image #matrix
--$sep
Content-Type: application/octet-stream
Content-Disposition: form-data; name="media[]"; filename="media.$ext"

EOF
			sub {
				if(@_) {
					warn "Had data of " . length($_[0]) . " bytes to write\n";
					$write->(shift);
					return 1;
				} else {
					warn "Termination\n";
					$write->("\x0D\x0A--${sep}--\x0D\x0A");
					$write->();
					return $resp;
				}
			}
		}
	)->then(sub {
		warn "Read done\n";
		$poster->on_done(sub {
			my ($resp) = @_;
			warn $resp->decoded_content;
		})->on_fail(sub {
		my ($error, $http, $resp) = @_;
		warn "pic post failed - " . $resp->code . $resp->decoded_content;
		})
	})
}

sub twat {
	my $msg = shift;
	my $uri = URI->new('https://api.twitter.com/1.1/statuses/update.json');
	my $content = 'status=' . uri_escape_utf8($msg);
	my $req = HTTP::Request->new(POST => $uri, [
		'Content-Type' => 'application/x-www-form-urlencoded',
	], $content);
	$req->header('Content-Length', length $content);
	$req->protocol('HTTP/1.1');
	my $hdr = $t->authorization_header(
		method     => 'POST',
		uri        => $uri,
		parameters => {
			status => $msg
		},
	);
	$req->header('Authorization' => $hdr);
	# say "Had auth header: $hdr";
	$req->header('Host' => $uri->host);
	$req->header('User-Agent' => 'OAuth gem v0.4.4');
#	$req->header('Connection' => 'close');
	$req->header('Accept' => '*/*');
	warn $req->as_string("\n");
	$ua->do_request(
		request => $req,
	)->on_done(sub {
		my ($resp) = @_;
		warn $resp->code . $resp->decoded_content;
	})->on_fail(sub {

		my ($error, $http, $resp) = @_;
		warn "failed - " . $resp->code . $resp->decoded_content;
	});
}

# twatpic('https://jki.re/_matrix/content/QGVyaWtqOmpraS5yZQiqKCsURYYzGPFkzjqHYRorOK.aW1hZ2UvanBlZw==.jpeg', 'test');
#twatpic('http://matrix.perlsite.co.uk/Screenshots/2014-09-03-1626%20room%20name.png', 'test');
#exit 0;
#twat('Hello World! #matrix');
#exit 0;
#
my $global_room;
$loop->add(my $matrix = Net::Async::Matrix->new(
	user_id => '@twitter:perlsite.co.uk',
	access_token => 'QHR3aXR0ZXI6cGVybHNpdGUuY28udWs..maahvOhGCQHBkvVivv',
	server => 'matrix.perlsite.co.uk:443',
	SSL => 1,
	SSL_verify_mode => SSL_VERIFY_NONE,
	on_log => sub {warn "log: @_\n" },
	on_room_new => sub {
      my ( $self, $room ) = @_;
	  warn "new room - $room\n";
	  $global_room = $room if $room->name =~ /matrix:/;
	  my $ready;
	  $room->configure(
	  	on_message => sub {
         my ( $self, $member, $content ) = @_;
		 return unless $ready;
         my $user = $member->user;
		 $user = $member->displayname // $user->user_id;
		 if($user->user_id eq $self->myself->user_id) {
		 	warn "this was from me, not posting: " . $content->{body};
			return;
		 }
		 my $msg = $user . ': ' . $content->{body} . ' #matrix';
		 if(ref $content->{body}) {
		 	my $uri =$content->{url}; 
			if(defined($uri)) {
				warn "Posting image: $uri\n";
#				my $f = twatpic($uri, $user)->on_ready(sub { warn " - $uri finished\n" });
#				$f->on_ready(sub { undef $f });
			} else {
				use Data::Dumper;
				warn "dunno what this is: " . Dumper($content);
			}
		 } else {
			warn "Posting message: $msg\n";
#			 my $f = twat($msg)->on_ready(sub { warn " - $msg finished\n" });
#			$f->on_ready(sub { undef $f });
		 }
		},
		on_synced_messages => sub { $ready = 1 },
	  );
	},

#	on_room_message => sub {
#		warn "Had message - @_";
#         my ( $self, $member, $content ) = @_;
#	}
));
sub log {
   my ( $line ) = @_;
   warn "broken log: $line\n";
}
#my $f; $f = $matrix->join_room('#client_test:localhost')->on_ready(sub { warn "joined\n"; undef $f });;
$matrix->start;

{
	my $uri = URI->new('https://userstream.twitter.com/1.1/user.json?replies=all');
	my $req = HTTP::Request->new(GET => "$uri");
	$req->protocol('HTTP/1.1');
	# $req->header(Authorization => 'Bearer ' . $t->req);
	my $hdr = $t->authorization_header(
		method => 'GET',
		uri => $uri,
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
			say "Header: " . $hdr->code . " " . $hdr->message;
			my $json = JSON::MaybeXS->new;
			sub {
				return unless @_;
				my $data = shift;
				my @found = $json->incr_parse($data);
				for(@found) {
					next unless exists $_->{text};
					say Dumper($_) unless defined $_->{text};
					say $_->{user}{screen_name} . ': ' . $_->{text};
					if(1) {
					my $f = $global_room->send_message(
						type => 'text',
						body => $_->{user}{screen_name} . ': ' . $_->{text}
					);
					$f->on_ready(sub { undef $f });
					}
				}
			}
		}
	);
}
$loop->run;

