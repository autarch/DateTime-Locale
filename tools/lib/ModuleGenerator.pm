package    # hide from PAUSE
    ModuleGenerator;

use v5.22;

use strict;
use warnings;
use feature qw( postderef signatures );
use namespace::autoclean;
use autodie;

use Data::Dumper::Concise qw( Dumper );
use JSON::MaybeXS qw( decode_json );
use List::AllUtils qw( max );
use ModuleGenerator::Locale;
use Locale::Language
    qw( language_code2code LOCALE_LANG_ALPHA_2 LOCALE_LANG_ALPHA_3 );
use Parse::PMFile;
use Path::Class qw( file );
use Path::Class::Rule;
use Scalar::Util qw( reftype );
use Text::Template;

use Moose;
use MooseX::Types::Moose qw( ArrayRef Bool Num Str );
use MooseX::Types::Path::Class qw( Dir File );

## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings qw( experimental::postderef experimental::signatures );
## use critic

with 'MooseX::Getopt::Dashes';

our $VERSION = '0.10';

has _autogen_warning => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    builder => '_build_autogen_warning',
);

has _script => (
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    builder => '_build_script',
);

has _source_data_root => (
    is      => 'ro',
    isa     => Dir,
    lazy    => 1,
    builder => '_build_source_data_root',
);

has _locale_codes => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    lazy    => 1,
    builder => '_build_locale_codes',
);

has _locales => (
    is      => 'ro',
    isa     => ArrayRef ['ModuleGenerator::Locale'],
    lazy    => 1,
    builder => '_build_locales',
);

sub run ($self) {
    $self->_clean_old_data;
    $self->_locales;
    $self->_write_data_pm;
    $self->_write_catalog_pm;
    $self->_write_pod_files;

    return 0;
}

sub _clean_old_data ($self) {
    my $pir  = Path::Class::Rule->new;
    my $iter = $pir->file->name(qr/\.pod$/)->iter('lib');
    while ( my $path = $iter->() ) {
        ## no critic (InputOutput::RequireCheckedSyscalls)
        say 'Removing ', $path->basename;
        $path->remove;
    }
}

sub _build_locales ($self) {
    my @locales;
    for my $code ( $self->_locale_codes->@* ) {
        my $locale = ModuleGenerator::Locale->instance(
            code             => $code,
            source_data_root => $self->_source_data_root,
        );

        ## no critic (InputOutput::RequireCheckedSyscalls)
        say $locale->code;
        say $_ for $locale->source_files;
        print "\n";
        ## use critic

        push @locales, $locale;
    }

    return \@locales;
}

sub _write_data_pm ($self) {
    my $data_pm_file = file(qw( lib DateTime Locale Data.pm ));
    ## no critic (InputOutput::RequireCheckedSyscalls)
    say "Generating $data_pm_file";
    ## use critic
    my $data_pm = $data_pm_file->slurp( iomode => '<:encoding(UTF-8)' );

    $self->_insert_autogen_warning( \$data_pm );

    my %codes;
    my %names;
    my %native_names;
    my %raw_locales;
    for my $locale ( $self->_locales->@* ) {
        $codes{ $locale->code }               = 1;
        $names{ $locale->en_name }            = 1;
        $native_names{ $locale->native_name } = 1;
        $raw_locales{ $locale->code }         = $locale->data_hash;
    }

    $self->_insert_var_in_code(
        'CLDRVersion',
        $self->_locales->[0]->version, 1, \$data_pm
    );

    $self->_insert_var_in_code( 'Codes',       \%codes,        1, \$data_pm );
    $self->_insert_var_in_code( 'Names',       \%names,        1, \$data_pm );
    $self->_insert_var_in_code( 'NativeNames', \%native_names, 1, \$data_pm );

    $self->_insert_var_in_code(
        'ISO639Aliases',
        $self->_iso_639_aliases, 1, \$data_pm
    );

    # These are some of the world's top languages by speakers plus a few
    # locales where I think there are lots of Perl people.
    my %preload = map { $_ => delete $raw_locales{$_} }
        qw( ar en en-CA en-US es fr-FR hi ja-JP pt-BR zh-Hans-CN zh-Hant-TW );

    $self->_insert_var_in_code( 'LocaleData', \%preload, 0, \$data_pm );

    my $pos = 0;
    my %index;
    my $data_section = q{};
    for my $code ( sort keys %raw_locales ) {
        my $marker = "__[ $code ]__\n";
        $data_section .= $marker;
        $pos += length $marker;

        my $start_pos = $pos;

        my $dumped = $self->_dump_with_unicode( $raw_locales{$code} );
        $data_section .= $dumped;
        $pos += length $dumped;

        $index{$code} = [ $start_pos => $pos - $start_pos ];
    }

    $self->_insert_var_in_code( 'DataSectionIndex', \%index, 0, \$data_pm );

    $data_pm =~ s/(__DATA__\n).*(__END__\n)/$1$data_section\n$2/s
        or die 'data section subst failed';

    $data_pm_file->spew( iomode => '>:encoding(UTF-8)', $data_pm );

    return;
}

sub _iso_639_aliases ($self) {
    my %aliases;
    for my $locale ( $self->_locales->@* ) {
        my $three = language_code2code(
            $locale->language_code,
            LOCALE_LANG_ALPHA_2, LOCALE_LANG_ALPHA_3
        ) or next;

        my $full_three_code = join '-',
            grep {defined} (
            $three,
            $locale->script_code,
            $locale->territory_code,
            $locale->variant_code
            );

        $aliases{$full_three_code} = $locale->code;
    }
    return \%aliases;
}

sub _write_catalog_pm ($self) {
    my $catalog_pm_file = file(qw( lib DateTime Locale Catalog.pm ));
    ## no critic (InputOutput::RequireCheckedSyscalls)
    say "Generating $catalog_pm_file";
    ## use critic
    my $catalog_pm = $catalog_pm_file->slurp( iomode => '<:encoding(UTF-8)' );

    my $max_code = max map { length $_->code } $self->_locales->@*;
    $max_code += 3;
    my $max_en_name = max map { length $_->en_name } $self->_locales->@*;
    $max_en_name += 3;
    my $max_native_name
        = max map { length $_->native_name } $self->_locales->@*;
    $max_native_name += 3;

    my $locale_list = sprintf(
        " %-${max_code}s%-${max_en_name}s%-${max_native_name}s\n",
        'Locale code', 'Locale name (in English)', 'Native locale name'
    );
    $locale_list
        .= q{ } . '=' x ( $max_code + $max_en_name + $max_native_name );
    $locale_list .= "\n";

    for my $locale ( sort { $a->code cmp $b->code } $self->_locales->@* ) {
        $locale_list .= sprintf(
            " %-${max_code}s%-${max_en_name}s%-${max_native_name}s\n",
            $locale->code, $locale->en_name, $locale->native_name,
        );
    }
    $locale_list .= "\n";

    $locale_list =~ s/ +$//mg;

    $catalog_pm =~ s/(^=for :locales\n\n).+^(?==)/$1$locale_list/ms
        or die 'locale list subst failed';

    $catalog_pm_file->spew( iomode => '>:encoding(UTF-8)', $catalog_pm );
}

sub _insert_var_in_code ( $self, $name, $value, $public, $code ) {
    my $sigil
        = !ref $value              ? '$'
        : reftype $value eq 'HASH' ? '%'
        :                            '@';

    my $safe;
    if ( ref $value ) {
        $safe = $self->_dump_with_unicode($value);
        $safe =~ s/^[\{\[]/(/;
        $safe =~ s/[\}\]]\n$/)/;
    }
    else {
        $safe = $value = is_Num($value) ? $value : B::perlstring($value);
    }

    my $declarator = $public ? 'our' : 'my';
    ${$code} =~ s/
        (\#<<<\n
         \#\#\#\Q :start $name:\E\n)
        .*
        (\#\#\#\Q :end $name:\E\n
         \#>>>\n)
    /$1$declarator $sigil$name = $safe;\n$2/xs
        or die "inserting $name failed";

    return;
}

# Data::Dumper dumps all Unicode characters using Perl's \x{feedad0g}
# syntax. If the character is in the 0x80-0xFF range, then Perl will not treat
# this as a UTF-8 char when it sees it (either at compile or eval time). We
# force it to use UTF-8 by replacing \x{feedad0g} with \N{U+feedad0g}, which
# is always interpreted as UTF-8.
sub _dump_with_unicode ( $self, $val ) {
    my $dumped = Dumper($val);
    $dumped =~ s/\\x\{([^}]+)\}/$self->_unicode_char_for($1)/eg;
    return $dumped;
}

sub _unicode_char_for ( $, $hex ) {
    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    my $num = eval '0x' . $hex;
    die $@ if $@;
    return '\N{U+' . sprintf( '%04x', $num ) . '}';
}

sub _insert_autogen_warning ( $self, $code ) {
    ${$code} =~ s/(?:^###+$).+(?:^###+$)\n+//ms;
    ${$code} =~ s/^/$self->_autogen_warning/e;
    return;
}

sub _build_autogen_warning ($self) {
    my $script = $self->_script->basename;

    return <<"EOF";
###########################################################################
#
# This file is partially auto-generated by the DateTime::Locale generator
# tools (v$VERSION). This code generator comes with the DateTime::Locale
# distribution in the tools/ directory, and is called $script.
#
# This file was generated from the CLDR JSON locale data. See the LICENSE.cldr
# file included in this distribution for license details.
#
# Do not edit this file directly unless you are sure the part you are editing
# is not created by the generator.
#
###########################################################################

EOF
}

sub _write_pod_files ($self) {
    my $template = Text::Template->new(
        TYPE   => 'FILE',
        SOURCE => file(qw( tools templates locale.pod ))->stringify,
    ) or die $Text::Template::ERROR;

    use lib 'lib';
    require DateTime;
    require DateTime::Locale;

    my @example_dts = (
        DateTime->new(
            year      => 2008,
            month     => 2,
            day       => 5,
            hour      => 18,
            minute    => 30,
            second    => 30,
            time_zone => 'UTC',
        ),
        DateTime->new(
            year      => 1995,
            month     => 12,
            day       => 22,
            hour      => 9,
            minute    => 5,
            second    => 2,
            time_zone => 'UTC',
        ),
        DateTime->new(
            year      => -10,
            month     => 9,
            day       => 15,
            hour      => 4,
            minute    => 44,
            second    => 23,
            time_zone => 'UTC',
        ),
    );

    for my $code ( DateTime::Locale->codes ) {
        my $underscore = $code =~ s/-/_/gr;

        my $pod_file
            = file( qw( lib DateTime Locale ), $underscore . '.pod' );
        ## no critic (InputOutput::RequireCheckedSyscalls)
        say "Generating $pod_file";
        ## use critic

        my $locale = DateTime::Locale->load($code)
            or die "Cannot load $code";

        my $filled = $template->fill_in(
            HASH => {
                autogen_warning => $self->_autogen_warning,
                name            => 'DateTime::Locale::' . $underscore,
                description => "Locale data examples for the $code locale.",
                example_dts => \@example_dts,
                locale      => \$locale,
            },
        ) or die $Text::Template::ERROR;

        $pod_file->spew( iomode => '>:encoding(UTF-8)', $filled );
    }

    return;
}

sub _build_script {
    return file($0);
}

sub _build_source_data_root ($self) {
    return $self->_script->parent->parent->subdir('source-data');
}

sub _build_locale_codes ($self) {
    my $avail
        = decode_json(
        $self->_source_data_root->file(qw( cldr-core availableLocales.json ))
            ->slurp( iomode => '<:raw' ) );
    my $default
        = decode_json(
        $self->_source_data_root->file(qw( cldr-core defaultContent.json ))
            ->slurp( iomode => '<:raw' ) );

    return [
        $avail->{availableLocales}{full}->@*,
        $default->{defaultContent}->@*
    ];
}

__PACKAGE__->meta->make_immutable;

1;
