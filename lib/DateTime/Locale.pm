package DateTime::Locale;

use strict;

use DateTime::LocaleCatalog;

use Params::Validate qw( validate validate_pos SCALAR );

use vars qw($VERSION);

$VERSION = 0.01;

BEGIN
{
    return unless $] >= 5.006;

    require utf8; import utf8;
}

my %Class;
my %DataForID;
my %NameToID;
my %NativeNameToID;
my %AliasToID;
my %IDToExtra;

sub register
{
    shift;

    foreach my $l ( ref $_[0] ? @{ $_[0] } : $_[0] )
    {
        my @p = %$l;
        my %p = validate( @p, { id                   => { type => SCALAR },
                                en_complete_name     => { type => SCALAR },
                                native_complete_name => { type => SCALAR, optional => 1 },
                                en_language      => { type => SCALAR, optional => 1 },
                                native_language  => { type => SCALAR, optional => 1 },
                                en_territory     => { type => SCALAR, optional => 1 },
                                native_territory => { type => SCALAR, optional => 1 },
                                en_variant       => { type => SCALAR, optional => 1 },
                                native_variant   => { type => SCALAR, optional => 1 },
                                class            => { type => SCALAR, optional => 1 },
                                replace          => { type => SCALAR, default => 0 },
                              } );

        my $id = $p{id};

        die "'\@' or '=' are not allowed in locale ids"
            if $id =~ /[\@=]/;
        die "You cannot replace an existing locale ('$id') unless you also specify the 'replace' parameter as true\n"
            if ! delete $l->{replace} && exists $DataForID{$id};

        $DataForID{$id} = $l;
        $NameToID{ $l->{en_complete_name} } = $id;

        my $native_complete_name =
            ( exists $l->{native_complete_name}
              ? $l->{native_complete_name}
              : $l->{en_complete_name}
            );

        $NativeNameToID{$native_complete_name} = $id;

        $Class{$id} = $l->{class} if defined exists $l->{class};
    }
}

sub registered_id
{
    shift;
    my ($id) = validate_pos( @_, { type => SCALAR } );

    return 1 if $AliasToID{$id};
    return 1 if $DataForID{$id};

    return 0;
}

sub add_aliases
{
    shift;

    my $aliases = ref $_[0] ? $_[0] : {@_};

    while ( my ( $alias, $id ) = each %$aliases )
    {
        die "Unregistered locale '$id' cannot be used as an alias target for $alias"
            unless __PACKAGE__->registered_id($id);

        die "Can't alias an id to itself"
            if $alias eq $id;

        # check for overwrite?

        # we don't want aliases to other "pure" (no data) aliases
        while ( ! exists $DataForID{$id} )
        {
            $id = $AliasToID{$id};
        }

        $AliasToID{$alias} = $id;
    }
}

sub remove_alias
{
    shift;
    my ($alias) = validate_pos( @_, { type => SCALAR } );

    return delete $AliasToID{$alias};
}

BEGIN
{
    __PACKAGE__->register( \@DateTime::Locale::Locales );
    __PACKAGE__->add_aliases( \%DateTime::Locale::Aliases );
}

sub ids              { wantarray ? keys %DataForID       : [ keys %DataForID      ] }
sub names            { wantarray ? keys %NameToID        : [ keys %NameToID       ] }
sub native_names     { wantarray ? keys %NativeNameToID  : [ keys %NativeNameToID ] }

{
    my %FORMAT_TYPES      = ( F => 0,      L => 1,      M => 2,        S => 3       );
    my %FORMAT_TYPE_NAMES = ( 0 => 'full', 1 => 'long', 2 => 'medium', 3 => 'short' );

    my $Default_date_format_length = $FORMAT_TYPES{M};
    my $Default_time_format_length = $FORMAT_TYPES{M};

    sub default_date_format_length { shift->_default_format_length(\$Default_date_format_length, @_) }
    sub default_time_format_length { shift->_default_format_length(\$Default_time_format_length, @_) }

    sub _default_format_length
    {
        shift;
        my $ref = shift;

        return $$ref unless @_;

        my ($format) = ( shift =~ /^(.)/ );

        die "Invalid format value" unless defined ( $format = $FORMAT_TYPES{ uc $format } );

        return $$ref = $format;
    }

    sub format_type
    {
        shift;

        return "" unless @_;
        return $FORMAT_TYPE_NAMES{ shift() } || '';
    }
}

# These are hardcoded for backwards comaptibility with the
# DateTime::Language code.
my %OldAliases =
    ( #'Afar'              => undef, # XXX
     'Amharic'           => 'am_ET',
     'Austrian'          => 'de_AT',
     'Brazilian'         => 'pt_BR',
     'Czech'             => 'cs_CZ',
     'Danish'            => 'da_DK',
         'Dutch'             => 'nl_NL',
     'English'           => 'en_US',
     'French'            => 'fr_FR',
     #      'Gedeo'             => undef, # XXX
     'German'            => 'de_DE',
     'Italian'           => 'it_IT',
     'Norwegian'         => 'no_NO',
     'Oromo'             => 'om_ET', # Maybe om_KE or plain om ?
     'Portugese'         => 'pt_PT',
     #      'Sidama'            => undef, # XXX
         'Somali'            => 'so_SO',
     'Spanish'           => 'es_ES',
     'Swedish'           => 'sv_SE',
     #      'Tigre'             => undef, # XXX
     'TigrinyaEthiopian' => 'ti_ET',
     'TigrinyaEritrean'  => 'ti_ER',
    );

sub load
{
    my $class = shift;
    my $name = shift;

    # Custom class registered by user
    if ( $Class{$name} )
    {
        return $Class{$name}->new;
    }

    # special case for backwards compatibility with DT::Language
    $name = $OldAliases{$name} if exists $OldAliases{$name};

    if ( exists $DataForID{$name} || exists $AliasToID{$name} )
    {
        return $class->_load_class_from_id($name);
    }

    foreach my $h ( \%NameToID, \%NativeNameToID )
    {
        return $class->_load_class_from_id( $h->{$name} )
            if exists $h->{$name};
    }

    if ( my $id = $class->_guess_id($name) )
    {
        return $class->_load_from_id($id);
    }
}

sub _guess_id
{
    my $class = shift;
    my $name = shift;

    # Strip off charset for LC_* ids : en_GB.UTF-8 etc
    $name =~ s/\..*$//;

    my ( $language, $territory, $variant ) = split /_/, $name;

    foreach my $id ( "\L$language\U$territory\U$variant",
                     "\L$language\U$territory",
                     lc $language
                   )
    {
        return $id
            if exists $DataForID{$id} || exists $AliasToID{$id};
    }
}

sub _load_class_from_id
{
    my $class = shift;
    my $id = shift;

    # We want the first alias for which there is data
    my $data_id = $id;
    while ( exists $AliasToID{$id} && ! exists $DataForID{$id} )
    {
        $data_id = $AliasToID{$data_id};
    }

    my $real_id = $id;

    # This is the real class, which may be nested under several
    # aliases
    while ( exists $AliasToID{$real_id} )
    {
        $real_id = $AliasToID{$real_id};
    }

    my $real_class = "DateTime::Locale::$real_id";

    eval "require $real_class";

    die $@ if $@;

    return $real_class->new( %{ $DataForID{$data_id} },
                             id => $id,
                           );
}

1;

__END__

=pod

=head1 NAME

DateTime::Locale - Localization support for DateTime

=head1 SYNOPSIS

  use DateTime::Locale;

  DateTime::Locale->default_date_format('full');
  DateTime::Locale->default_time_format('medium');

  my $loc = DateTime::Locale->load('en_GB');

  print $loc->native_locale_name,    "\n",
        $loc->default_date_format,   "\n",
        $loc->default_time_format,   "\n",
	$loc->long_date_time_format, "\n";

  # but mostly just things like ...

  my $dt = DateTime->now( locale => 'fr' );
  print "Aujord'hui le mois est " . $dt->month_name, "\n":

=head1 DESCRIPTION

DateTime::Locale is primarily a factory for the various locale
subclasses.  It also provides some functions for getting information
on available locales.

If you want to know what methods are available for locale objects,
then please read the C<DateTime::Locale::Base> documentation.

=head1 USAGE

This module provides the following class methods:

=over 4

=item * load ( $locale_id | $locale_name | $alias )

=item * load ( $locale_id | $locale_name | $alias )

Returns the locale object for the specified locale id, name, or alias
- see the C<DateTime::LocaleCatalog> documentation for a list of built
in names and ids.

If the requested locale is not found, a fallback search takes place to
find a suitable replacement.

The fallback search order is:

  language_territory_variant
  language_territory
  language

Eg. For locale C<es_XX_UNKNOWN> the fallback search would be:

  es_XX_UNKNOWN   # Fails - no such locale
  es_XX           # Fails - no such locale
  es              # Found - the es locale is returned as the
                  # closest match to the requested id

If no suitable replacement is found, then an exception is thrown.

=item * ids

Returns an unsorted list of the available locale ids, or an
array reference if called in a scalar context.

Examples:

  my @ids = DateTime::Locale->ids;
  my $ids = DateTime::Locale->ids;

=item * id ( $locale_name )

Returns the locale id for the given locale name, or undef if no
matching locale id is found.

Example:

  my $id = DateTime::Locale->id("Uzbek_Uzbekistan");  # Returns "uz_UZ"

=item * names

Returns an unsorted list of the available locale names in English, or
an array reference if called in a scalar context.

Examples:

  my @names = DateTime::Locale->names;
  my $names = DateTime::Locale->names;

=item * name ( $locale_id | $locale )

Returns the locale name for the given locale id or object in English,
or undef if no matching locale name is found.

Locale names may consist of language, territory, and variant
components.  Use the C<language()>, C<territory()>, and C<variant()>
methods to access each component separately.

Example:

  my $name = DateTime::Locale->name("es_CO");  # Returns "Spanish Colombia"

  or:

  my $locale = DateTime::Locale->load("es_CO");
  my $name   = DateTime::Locale->name($locale);

=item * language  ( $locale_id | $locale )

=item * territory ( $locale_id | $locale )

=item * variant   ( $locale_id | $locale )

Returns the language, territory, and variant respectively of the given
locale id or object in English, or undef if that component does not
exist.

Example:

  DateTime::Locale->language("is_IS");        # Returns "Icelandic"

  DateTime::Locale->territory("ar_AE");       # Returns "United Arab Emirates"

  DateTime::Locale->variant("en_US_POSIX");   # Returns "POSIX"

=item * native_names

Returns an unsorted list of the available locale names in their native
language, or an array reference if called in a scalar context. All
native names are utf8 encoded.

B<NB>: Many locales are only partially translated, so some native
locale names may still be in English.

Examples:

  my @names = DateTime::Locale->native_names;
  my $names = DateTime::Locale->native_names;

=item * native_name ( $locale_id | $locale )

Returns the locale name in its native language for the given locale id
or object, or undef if no matching locale name is found.  All native
names are utf8 encoded.

Native names may consist of language, territory, and variant
components.  Use the L<native_language>, L<native_territory> and
L<native_variant> methods to access each component separately.

B<NB> Many locales are only partially translated, so the native locale
name may still be in English.

Example:

  my $name = DateTime::Locale->native_name("pl_PL");  # Returns "polski_Polska"

  or:

  my $locale = DateTime::Locale->load("pl_PL");
  my $name   = DateTime::Locale->native_name($locale);

=item * native_language  ( $locale_id | $locale )

=item * native_territory ( $locale_id | $locale )

=item * native_variant   ( $locale_id | $locale )

Returns the language, territory, and variant respectively of the given
locale id or object in its utf8 encoded native language, or undef if
that component does not exist.

B<NB> Many locales are only partially translated, so the returned components
may still be in English.

  # Returns "íslenska"
  DateTime::Locale->native_language("is_IS");

  # Returns "Magyarország"
  DateTime::Locale->native_territory("hu_HU");

At the moment, the value of C<native_variant()> and C<variant()> are
always the same.

=item * default_date_format ( $format_type )

Sets the default date format pattern used for outputting localized
dates and datetime combinations.

C<$format_type> must be one of: C<'full'>, C<'long'>, C<'medium'>, or
C<'short'>.

If no argument is supplied, the value returned is an index for the
array returned by the locale C<date_formats> method. See
L<DateTime::Locale::Base> for details of C<date_formats>.

See also: L<format_type>

Examples:

  DateTime::Locale->default_date_format('Long');

  my $format = $locale->date_formats->[ DateTime::Locale->default_date_format ];   # Returns the long date format pattern.

  DateTime::Locale->format_type( DateTime::Locale->default_date_format );          # Returns "Long".

=item * default_time_format ( $format_type )

Sets the default time format pattern used for outputting localized time
and datetime combinations.

C<$format_type> must be one of: C<'full'>, C<'long'>, C<'medium'>, or
C<'short'>.

If no argument is supplied, the value returned is an index for the
array returned by the locale C<time_formats> method. See
L<DateTime::Locale::Base> for details of C<time_formats>.

Examples:

  DateTime::Locale->default_time_format('medium');

  # Returns the medium time format pattern.
  my $format =
      $locale->time_formats->[ DateTime::Locale->default_time_format ];

  # Returns "medium".
  DateTime::Locale->format_type( DateTime::Locale->default_time_format );

=item * format_type ( $format_type_array_index )

Returns a string describing the passed format type array index as
returned by L<default_date_format> and L<default_time_format>.

The returned string is one of: C<'full'>, C<'long'>, C<'medium'>,
C<'short'>, or undef if the passed index was invalid.

=item * add_aliases ( $alias1 => $id1, $alias2 => $id2, ... )

Adds an alias to an existing locale id. This allows a locale to be
load()ed by its alias rather than id or name. Multiple aliases are
allowed.

If the passed locale id is neither registered nor listed in
L</AVAILABLE LOCALES>, an exception is thrown.

Example:

 DateTime::Locale->add_aliases( LastResort => 'es_ES' );

 # Equivalent to DateTime::Locale->load('es_ES');
 DateTime::Locale->load('LastResort');

You can also pass a hash reference to this method.

Example:

 DateTime::Locale->add_alias( { Default     => 'en_GB',
                                Alternative => 'en_US',
                                LastResort  => 'es_ES' } );

=item * remove_alias ( $alias )

Removes a locale id alias.  Non-existent aliases are silently ignored.

 DateTime::Locale->add_alias(LastResort => 'es_ES');

 # Equivalent to DateTime::Locale->load('es_ES');
 DateTime::Locale->load('LastResort');

 DateTime::Locale->remove_alias('LastResort');

 # Throws exception, 'LastResort' no longer exists
 DateTime::Locale->load('LastResort');

=item * register( ... )

Until registered, custom locales cannot be instantiated via load() and
will not be list by querying methods such as ids() or names().

 register( id               => $locale_id,

           # something like 'Language Territory Variant'
           en_complete_name     => $locale_name,

           # Optional - same as en_complete_name if omitted
           native_complete_name => $utf8_native_complete_name,

           # Optional - defaults to DateTime::Locale::$locale_id
           class                => $class_name,

           # Other optional keys include:

           # Just the singular components
           en_language => ...,
           en_territory => ...,
           en_variant   => ...,

           native_language  => ...,
           native_territory => ...,
           native_variant   => ...,
         )

The locale id and name are required, and the following formats should
used wherever possible:

 id:   languageId[_territoryId[_variantId]]

 Where:  languageId = Lower case ISO  639 code -
          Always choose  639-1 over  639-2 where possible.

 territoryId = Upper case ISO 3166 code -
               Always choose 3166-1 over 3166-2 where possible.

 variantId = Upper case variant id -
             Basically anything you want, since this is typically the
             component that uniquely identifies a custom locale.

You cannot not use '@' or '=' in locale ids - these are reserved for
future use.  The underscore (_) is the component separator, and should
not be used for any other purpose.

 en_complete_name: language[ territory[ variant]]

  Where:    language = Mixed case language name in English.
           territory = Mixed case territory name in English.
             variant = Mixed case string describing the variant id in English.

If native_name is supplied, it must be utf8 encoded and follow:

 native_complete_name: language[ territory[ variant]]

  Where:    language = Mixed case language name in native language.
           territory = Mixed case territory name in native language.
             variant = Mixed case string describing the variant id in native language.

If omitted, the complete native name is assumed to be identical to the
English name.

If class is supplied, it must be the full module name of your custom
locale. If omitted, the locale module is assumed to be a
DateTime::Locale subclass.

Examples:

 DateTime::Locale->register
     ( id => 'en_GB_RIDAS',
       en_complete_name => 'English United Kingdom Ridas custom locale' );

 # Returns instance of class DateTime::Locale::en_GB_RIDAS
 my $l = DateTime::Locale->load('en_GB_RIDAS');

 DateTime::Locale->register
     ( id => 'hu_HU',
       en_complete_name     => 'Hungarian Hungary',
       native_complete_name => 'magyar Magyarország' );

 # Returns instance of class DateTime::Locale::hu_HU
 my $l = DateTime::Locale->load('hu_HU');


 DateTime::Locale->register
     ( id    => 'en_GB_RIDAS',
       name  => 'English United Kingdom Ridas custom locale',
       class => 'Ridas::Locales::CustomGB' );

 # Returns instance of class Ridas::Locales::CustomGB
 # NOT Ridas::Locales::Custom::en_GB_RIDAS !
 my $l = DateTime::Locale->load('en_GB_RIDAS');

=head1 ADDING CUSTOM LOCALES

These are added in one of two ways:

=over 4

=item 1.

Subclass an existing locale implementing only the changes you require.

=item 2.

Create a completely new locale.

=back 4

In either case the locale MUST be registered before use.

=head2 Subclass an existing locale.

The following example sublasses the United Kingdom English locale to
provide different date/time formats:

  package Ridas::Locale::en_GB_RIDAS1;

  use strict;
  use DateTime::Locale::en_GB;

  @Ridas::Locale::en_GB_RIDAS1::ISA = qw ( DateTime::Locale::en_GB );

  my $locale_id = 'en_GB_RIDAS1';

  my $date_formats =
  [
    "%A %{day} %B %{ce_year}",
    "%{day} %B %{ce_year}",
    "%{day} %b %{ce_year}",
    "%{day}/%m/%y",
  ];

  my $time_formats =
  [
    "%H h  %{minute} %{time_zone_short_name}",
    "%{hour12}:%M:%S %p",
    "%{hour12}:%M:%S %p",
    "%{hour12}:%M %p",
  ];

  sub id           { $locale_id    }
  sub date_formats { $date_formats }
  sub time_formats { $time_formats }

  1;

Now register it:

 DateTime::Locale->register
     ( id    => 'en_GB_RIDAS1',
       name  => 'English United Kingdom Ridas custom locale 1',
       class => 'Ridas::Locale::en_GB_RIDAS1' );

=head2 Creating a completely new locale

Inherit directly from DateTime::Locale::Base, and implement the
following methods:

  id
  month_names
  month_abbreviations
  day_names
  day_abbreviations
  am_pms
  eras
  date_formats
  time_formats
  date_time_format_pattern_order

See C<DateTime::Locale::Base> for a description of each method, and
take a look at DateTime/Locale/root.pm for an example of a complete
implementation.

Once created, remember to register it!

Of course, you can always do the registration in the module itself,
and simply load it before using it.

=head1 SUPPORT

Please be aware that all locale data has been generated from either
the Common XML Locale Repository project locales (originally ICU
locale data) or the Yeha project.  The data B<is> currently
incomplete, and B<will> contain errors in some locales.

When reporting errors in data, please check the primary data sources
first, then where necessary report errors directly to the primary
source:

  Common XML Locale Repository/ICU : fsg.openi18n.locale.user    newsgroup
  Yeha                             : http://yeha.sourceforge.net

Once these errors have been confirmed, please forward the error
report, and corrections to DateTime.

Support for this module is provided via the datetime@perl.org email
list. See http://lists.perl.org/ for more details.

=head1 AUTHORS

Richard Evans <rich@ridas.com>

Dave Rolsky <autarch@urth.org>

These modules are based on the DateTime::Language modules, which were
in turn based on the Date::Language modules from Graham Barr's
TimeDate distribution.

Thanks to Rick Measham for providing the Java to strftime pattern
conversion routines used during locale generation.

=head1 COPYRIGHT

Copyright (c) 2003 Richard Evans. All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

The locale modules in directory C<DateTime/Locale/> have been
generated from data provided by the Common XML Locale Repository
project, see C<DateTime/Locale/LICENSE.icu> for licensing details.

=head1 SEE ALSO

L<DateTime::Locale::Base>

datetime@perl.org mailing list

http://datetime.perl.org/

=cut

