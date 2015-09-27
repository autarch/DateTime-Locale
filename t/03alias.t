use strict;
use warnings;

use Test::More;
use Test::Fatal;

use DateTime::Locale;

DateTime::Locale->add_aliases( foo => 'root' );
DateTime::Locale->add_aliases( bar => 'foo' );
DateTime::Locale->add_aliases( baz => 'bar' );
like(
    exception { DateTime::Locale->add_aliases( bar => 'baz' ) },
    qr/loop/,
    'cannot add an alias that would cause a loop'
);

my $l = DateTime::Locale->load('baz');
isa_ok( $l, 'DateTime::Locale::FromData' );
is( $l->id, 'root', 'id is root' );

ok(
    DateTime::Locale->remove_alias('baz'),
    'remove_alias should return true'
);

like(
    exception { DateTime::Locale->load('baz') },
    qr/invalid/i,
    'removed alias should be gone'
);

done_testing();
