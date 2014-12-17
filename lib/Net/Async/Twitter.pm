package Net::Async::Twitter;
# ABSTRACT: basic Twitter API support for IO::Async
use strict;
use warnings;

use parent qw(IO::Async::Notifier);

our $VERSION = '0.001';

=head1 NAME

Net::Async::Twitter - basic Twitter support for IO::Async

=head1 DESCRIPTION

This is an early experimental release. Things are likely to change. See
the examples/ directory in the source distribution.

=head1 METHODS

=cut

use MIME::Base64 qw(encode_base64 decode_base64);
use URI::Escape qw(uri_escape_utf8);
use Digest::HMAC;
use Digest::SHA1;
use List::UtilsBy qw(sort_by);
use Future::Utils qw(repeat);
use JSON::MaybeXS;

{
my @chars = ('a'..'z', 'A' .. 'Z', '0'..'9');

=head2 oauth_nonce

Generates a 32-character pseudo random string.

If security is an important consideration, you may want to override this
with an algorithm that uses something stronger than L<rand>.

=cut

sub oauth_nonce {
	my $self = shift;
	join('', map $chars[@chars * rand], 1..32)
}
}

=head2 configure

Applies configuration.

=over 4

=item * consumer_key

=item * consumer_secret

=item * token_secret

=back


=cut

sub configure {
	my ($self, %args) = @_;
	for(qw(consumer_key consumer_secret token_secret)) {
		$self->{$_} = delete $args{$_} if exists $args{$_};
	}
	$self->SUPER::configure(%args);
}

=head1 oauth_fields

Generates signature information for the given request.

=over 4

=item * url - the URL we're requesting

=item * method - GET/POST for HTTP method

=item * parameters - hashref of parameters we're sending

=back

Returns a hashref which contains information.

=cut

sub oauth_fields {
	my $self = shift;
	my %args = @_;
	my $uri = delete($args{uri}) || URI->new($args{url});

	my %info = (
		oauth_signature_method => $self->signature_method,
		oauth_nonce            => $args{nonce} // $self->oauth_nonce,
		oauth_consumer_key     => $self->consumer_key,
		oauth_timestamp        => time,
		oauth_version          => $self->oauth_version,
		oauth_token            => $self->token,
	);

	my $bare_uri = $uri->clone;
	$bare_uri->query_form({});

	$info{oauth_signature} = $self->sign(
		method => $args{method},
		url => "$bare_uri",
		parameters => {
			$uri->query_form,
			%{ $args{parameters} || {} },
			%info
		},
	);
	return \%info;
}

=head2 sign

=cut

sub sign {
	my $self = shift;
	my %args = @_;
	my $parameters = $self->parameter_string($args{parameters});
	my $base = $self->signature_base(
		%args,
		parameters => $parameters
	);
#	warn "base=$base\n";
	my $signing_key = $self->signing_key;
	my $digest = Digest::HMAC->new($signing_key, 'Digest::SHA1');
	$digest->add($base);
	my $signature = $digest->b64digest;

	# Pad to multiple-of-4
	$signature .= '=' while length($signature) % 4;
	return $signature;
}

=head2 signing_key

=cut

sub signing_key {
	my $self = shift;
	join '&', map uri_escape_utf8($_), $self->consumer_secret, $self->token_secret;
}

=head2 parameter_string

=cut

sub parameter_string {
	my ($self, $param) = @_;
	join '&', map {
		uri_escape_utf8($_) . '=' . uri_escape_utf8($param->{$_})
	} sort_by { uri_escape_utf8($_) } keys %$param;
}

=head2 signature_base

=cut

sub signature_base {
	my ($self, %args) = @_;
	join '&', map uri_escape_utf8($_), uc($args{method}), $args{url}, $args{parameters};
}

=head2 oauth_consumer_key

=cut

sub oauth_consumer_key { shift->{oauth_consumer_key} }


=head2 oauth_signature_method

=cut

sub oauth_signature_method { 'HMAC-SHA1' }

=head2 oauth_version

=cut

sub oauth_version { '1.0' }

=head2 token

=cut

sub token { shift->{token} }

=head2 secret

=cut

sub secret { shift->{secret} }

=head2 consumer_key

=cut

sub consumer_key { shift->{consumer_key} }

=head2 consumer_secret

=cut

sub consumer_secret { shift->{consumer_secret} }

=head2 token_secret

=cut

sub token_secret { shift->{token_secret} }

=head2 signature_method

=cut

sub signature_method { 'HMAC-SHA1' }

=head2 req

I have no idea why this is here.

=cut

sub req {
	my $self = shift;
	my $req = encode_base64(join(':', $self->token, $self->secret), '');
#	POST '/oauth2/token'
}

=head2 parameters_from_request

=cut

sub parameters_from_request {
	my ($self, $req) = @_;
	my $uri = $req->uri->clone->query_form({});
	my %param = $req->uri->query_form;
	# POST, PATCH, PUT
	if($req->method =~ /^P/) {
		my %body_param = map { split /=/, $_, 2 } split /&/, $req->decoded_content;
		$param{$_} = $body_param{$_} for keys %body_param;
	}
	return \%param;
}

=head2 authorization_header

=cut

sub authorization_header {
	my ($self, %args) = @_;
	my $oauth = $self->oauth_fields(%args);
	return 'OAuth ' . join(',', map { $_ . '="' . uri_escape_utf8($oauth->{$_}) . '"' } sort keys %$oauth);
}

=head2 userstream

Does the userstream thing.

=cut

sub userstream {
	my ($self, $code) = @_;

	my $uri = URI->new('https://userstream.twitter.com/1.1/user.json?replies=all');
	my $req = HTTP::Request->new(GET => "$uri");
	$req->protocol('HTTP/1.1');

	# $req->header(Authorization => 'Bearer ' . $self->req);
	my $hdr = $self->authorization_header(
		method => 'GET',
		uri => $uri,
	);
	$req->header('Authorization' => $hdr);
	$self->debug_printf("Resulting auth header for userstream was %s", $hdr);

	$req->header('Host' => $uri->host);
	$req->header('User-Agent' => 'OAuth gem v0.4.4');
	$req->header('Connection' => 'close');
	$req->header('Accept' => '*/*');
	repeat {
		$self->ua->do_request(
			request => $req,
			on_header => sub {
				my $hdr = shift;
				$self->debug_printf("Response code was %d - %s", $hdr->code, $hdr->message);
				my $json = JSON::MaybeXS->new;
				sub {
					return unless @_;
					my $data = shift;
					$json->incr_parse($data);

					my @found = $json->incr_parse;
					for my $item (@found) {
						$code->($item);
					}
				}
			}
		);
	} while => sub { 1 };
}

=head2 stream

Watch for messages matching given keywords.

 $twitter->stream(sub {
  warn "Had @_"
 }, qw(perl5 perl cpan))

=cut

sub stream {
	my ($self, $code, @keywords) = @_;
	die "No keywords supplied" unless @keywords;

	my $uri = URI->new('https://stream.twitter.com/1.1/statuses/filter.json');
	$uri->query_param(track => join ',', map uri_escape_utf8($_), @keywords);
	my $req = HTTP::Request->new(GET => "$uri");
	$req->protocol('HTTP/1.1');

	# $req->header(Authorization => 'Bearer ' . $self->req);
	my $hdr = $self->authorization_header(
		method => 'GET',
		uri    => $uri,
	);
	$req->header('Authorization' => $hdr);
	$self->debug_printf("Resulting auth header for userstream was %s", $hdr);

	$req->header('Host' => $uri->host);
	$req->header('User-Agent' => 'OAuth gem v0.4.4');
	$req->header('Connection' => 'close');
	$req->header('Accept' => '*/*');

	repeat {
		$self->ua->do_request(
			request => $req,
			on_header => sub {
				my $hdr = shift;
				$self->debug_printf("Response code was %d - %s", $hdr->code, $hdr->message);
				my $json = JSON::MaybeXS->new;
				sub {
					return unless @_;

					my $data = shift;
					$json->incr_parse($data);

					my @found = $json->incr_parse;
					for my $item (@found) {
						$code->($item);
					}
				}
			}
		);
	} while => sub { 1 };
}

=head2 ua

=cut

sub ua {
	my ($self) = @_;
	unless($self->{ua}) {
		$self->add_child(
			$self->{ua} = Net::Async::HTTP->new(
				fail_on_error            => 1,
				max_connections_per_host => 4,
				pipeline                 => 0,
				max_in_flight            => 1,
			)
		);
	}
	return $self->{ua};
}

1;

__END__

=head1 SEE ALSO

All the other twitter clients and libraries. There's a few of them.

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2012-2014. Licensed under the same terms as Perl itself.

