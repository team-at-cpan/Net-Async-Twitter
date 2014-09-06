package Net::Async::Twitter;
# ABSTRACT: basic Twitter API support for IO::Async
use strict;
use warnings;

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

sub new { my $class = shift; bless { @_ }, $class }

{
	my @chars = ('a'..'z', 'A' .. 'Z', '0'..'9');
	sub oauth_nonce {
		my $self = shift;
		join('', map $chars[@chars * rand], 1..32)
	}
}

sub oauth_consumer_key { shift->{oauth_consumer_key} }

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
		oauth_nonce => $args{nonce} // $self->oauth_nonce,
		oauth_consumer_key => $self->consumer_key,
		oauth_timestamp => time,
		oauth_signature_method => $self->signature_method,
		oauth_version => $self->oauth_version,
		oauth_token => $self->token,
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

sub signing_key {
	my $self = shift;
	join '&', map uri_escape_utf8($_), $self->consumer_secret, $self->token_secret;
}

sub parameter_string {
	my ($self, $param) = @_;
	join '&', map {
		uri_escape_utf8($_) . '=' . uri_escape_utf8($param->{$_})
	} sort_by { uri_escape_utf8($_) } keys %$param;
}

sub signature_base {
	my ($self, %args) = @_;
	join '&', map uri_escape_utf8($_), uc($args{method}), $args{url}, $args{parameters};
}

sub oauth_signature_method { 'HMAC-SHA1' }
sub oauth_version { '1.0' }
sub token { shift->{token} }
sub secret { shift->{secret} }
sub consumer_key { shift->{consumer_key} }
sub consumer_secret { shift->{consumer_secret} }
sub token_secret { shift->{token_secret} }
sub signature_method { 'HMAC-SHA1' }

sub req {
	my $self = shift;
	my $req = encode_base64(join(':', $self->token, $self->secret), '');
#	POST '/oauth2/token'
}

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

sub authorization_header {
	my ($self, %args) = @_;
	my $oauth = $self->oauth_fields(%args);
	return 'OAuth ' . join(',', map { $_ . '="' . uri_escape_utf8($oauth->{$_}) . '"' } sort keys %$oauth);
}

1;

__END__

=head1 SEE ALSO

All the other twitter clients and libraries...

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2012-2014. Licensed under the same terms as Perl itself.

