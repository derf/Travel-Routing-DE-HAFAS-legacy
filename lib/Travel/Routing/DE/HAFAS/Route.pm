package Travel::Routing::DE::HAFAS::Route;

use strict;
use warnings;
use 5.010;

no if $] >= 5.018, warnings => 'experimental::smartmatch';

use parent 'Class::Accessor';

use DateTime;
use Travel::Routing::DE::HAFAS::Route::Part;

our $VERSION = '0.00';

Travel::Routing::DE::HAFAS::Route->mk_ro_accessors(qw(delay service_days));

sub new {
	my ( $obj, $info, @parts ) = @_;

	my $ref = $info;

	$ref->{base_date} = DateTime->new(
		year      => 1979,
		month     => 12,
		day       => 31,
		time_zone => 'Europe/Berlin',    # hardcoded for now
	)->add( days => $ref->{date} );

	if ( $ref->{delay} == 255 ) {
		$ref->{delay} = undef;           # probably "no realtime data"
	}

	for my $part (@parts) {
		$part->{base_date_ref} = $ref->{base_date};
		push(
			@{ $ref->{parts} },
			Travel::Routing::DE::HAFAS::Route::Part->new( %{$part} )
		);
	}

	return bless( $ref, $obj );
}

sub parts {
	my ($self) = @_;

	return @{ $self->{parts} };
}

sub is_cancelled {
	my ($self) = @_;

	if ( $self->{realtime_status} == 2 ) {
		return 1;
	}
	return;
}

sub TO_JSON {
	my ($self) = @_;

	return { %{$self} };
}

1;

__END__

=head1 NAME

Travel::Status::DE::HAFAS::Route - Information about a single
arrival/departure received by Travel::Status::DE::HAFAS

=head1 SYNOPSIS

	for my $departure ($status->results) {
		printf(
			"At %s: %s to %s from platform %s\n",
			$departure->time,
			$departure->line,
			$departure->destination,
			$departure->platform,
		);
	}

	# or (depending on module setup)
	for my $arrival ($status->results) {
		printf(
			"At %s: %s from %s on platform %s\n",
			$arrival->time,
			$arrival->line,
			$arrival->origin,
			$arrival->platform,
		);
	}

=head1 VERSION

version 0.00

=head1 DESCRIPTION

Travel::Status::DE::HAFAS::Route describes a single arrival/departure
as obtained by Travel::Status::DE::HAFAS.  It contains information about
the platform, time, route and more.

=head1 METHODS

=head2 ACCESSORS

=over

=item $result->date

Arrival/Departure date in "dd.mm.yyyy" format.

=item $result->delay

Returns the train's delay in minutes, or undef if it is unknown.

=item $result->info

Returns additional information, for instance the reason why the train is
delayed. May be an empty string if no (useful) information is available.

=item $result->is_cancelled

True if the train was cancelled, false otherwise.

=item $result->line

=item $result->train

Returns the line name, either in a format like "S 1" (S-Bahn line 1)
or "RE 10111" (RegionalExpress train 10111, no line information).

=item $result->platform

Returns the platform from which the train will depart / at which it will
arrive.

=item $result->route

Returns a list of station names the train will pass between the selected
station and its origin/destination.

=item $result->route_end

Returns the last element of the route.  Depending on how you set up
Travel::Status::DE::HAFAS (arrival or departure listing), this is
either the train's destination or its origin station.

=item $result->destination

=item $result->origin

Convenience aliases for $result->route_end.

=item $result->route_interesting([I<max>])

Returns a list of up to I<max> (default: 3) interesting stations the train
will pass on its journey. Since deciding whether a station is interesting or
not is somewhat tricky, this feature should be considered experimental.

The first element of the list is always the train's next stop. The following
elements contain as many main stations as possible, but there may also be
smaller stations if not enough main stations are available.

In future versions, other factors may be taken into account as well.  For
example, right now airport stations are usually not included in this list,
although they should be.

Note that all main stations will be stripped of their "Hbf" suffix.

=item $result->route_raw

Returns the raw string used to create the route array.

Note that cancelled stops are filtered from B<route>, but still present in
B<route_raw>.

=item $result->route_timetable

Similar to B<route>.  however, this function returns a list of array
references of the form C<< [ arrival time, station name ] >>.

=item $result->route_info

Returns a string containing information related to the train's route, such as
"landslide between X and Y, expect delays".

=item $result->time

Returns the arrival/departure time as string in "hh:mm" format.

=item $result->type

Returns the type of this train, e.g. "S" for S-Bahn, "RE" for Regional Express
or "ICE" for InterCity-Express.

=back

=head2 INTERNAL

=over

=item $result = Travel::Status::DE::HAFAS::Result->new(I<%data>)

Returns a new Travel::Status::DE::HAFAS::Result object.
You usually do not need to call this.

Required I<data>:

=over

=item B<time> => I<hh:mm>

=item B<train> => I<string>

=item B<route_raw> => I<string>

=item B<route> => I<arrayref>

=item B<route_end> => I<string>

=item B<platform> => I<string>

=item B<info_raw> => I<string>

=back

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item Class::Accessor(3pm)

=back

=head1 BUGS AND LIMITATIONS

None known.

=head1 SEE ALSO

Travel::Status::DE::HAFAS(3pm).

=head1 AUTHOR

Copyright (C) 2011 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
