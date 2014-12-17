use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Net::Async::Twitter;

my $t = new_ok('Net::Async::Twitter');

like(exception {
	$t->stream(sub { })
}, qr/^No keywords supplied/, 'raises exception if given nothing to track');

done_testing;

