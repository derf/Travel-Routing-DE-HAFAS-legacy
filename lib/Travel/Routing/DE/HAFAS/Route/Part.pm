package Travel::Routing::DE::HAFAS::Route::Part;

use strict;
use warnings;
use 5.010;

no if $] >= 5.018, warnings => "experimental::smartmatch";

use parent 'Class::Accessor';

our $VERSION = '0.00';

Travel::Routing::DE::HAFAS::Route::Part->mk_ro_accessors(
	qw(arrival_datetime arrival_stop arrival_platform
	  departure_datetime departure_stop departure_platform
	  delay arrival_delay departure_delay
	  destination line has_realtime
	  sched_arrival_datetime sched_departure_datetime
	  sched_arrival_platform sched_departure_platform
	  )
);

# destination: may be undef (e.g. for Fussweg)

sub new {
	my ( $obj, %conf ) = @_;

	my $ref = \%conf;

	$ref->{destination} = $ref->{attributes}{Direction};

	# Never operate on $base_date_ref directly, always use ->clone first
	my $base_date_ref = $ref->{base_date_ref};

	if ( defined $ref->{attributes}{Category} ) {
		$ref->{attributes}{Category} =~ s{ \s+ $ }{}x;
	}

	if (    defined $ref->{attributes}{Category}
		and defined $ref->{attributes}{Number} )
	{
		$ref->{line}
		  = $ref->{attributes}{Category} . q{ } . $ref->{attributes}{Number};
	}
	elsif ( defined $ref->{attributes}{HafasName} ) {
		$ref->{line} = $ref->{attributes}{HafasName};
	}

	for my $rt_time (qw(rt_arr_time rt_dep_time)) {
		if ( $ref->{$rt_time} == 65535 ) {
			$ref->{$rt_time} = undef;
		}
	}
	for my $str (qw(arr_platform dep_platform rt_arr_platform rt_dep_platform))
	{
		if ( defined $ref->{$str} and $ref->{$str} eq '---' ) {
			$ref->{$str} = undef;
		}
	}

	for my $time (qw(arr_time dep_time rt_arr_time rt_dep_time)) {
		if ( defined $ref->{$time} ) {
			my $day_offset = int( $ref->{$time} / 2400 );
			$ref->{$time} %= 2400;
			my $hour   = int( $ref->{$time} / 100 );
			my $minute = $ref->{$time} % 100;

			$ref->{$time} = $base_date_ref->clone->add(
				days    => $day_offset,
				hours   => $hour,
				minutes => $minute,
			);
		}
	}

	if ( defined $ref->{rt_arr_time} ) {
		$ref->{arrival_delay}
		  = $ref->{rt_arr_time}->subtract_datetime( $ref->{arr_time} )
		  ->in_units('minutes');
	}
	if ( defined $ref->{rt_dep_time} ) {
		$ref->{departure_delay}
		  = $ref->{rt_dep_time}->subtract_datetime( $ref->{dep_time} )
		  ->in_units('minutes');
	}

	$ref->{arrival_datetime}   = $ref->{rt_arr_time} // $ref->{arr_time};
	$ref->{departure_datetime} = $ref->{rt_dep_time} // $ref->{dep_time};
	$ref->{sched_arrival_datetime}   = $ref->{arr_time};
	$ref->{sched_departure_datetime} = $ref->{dep_time};

	$ref->{delay} = $ref->{departure_delay} // $ref->{arrival_delay};

	$ref->{arrival_platform} = $ref->{rt_arr_platform} // $ref->{arr_platform};
	$ref->{sched_arrival_platform} = $ref->{arr_platform};

	$ref->{departure_platform} = $ref->{rt_dep_platform}
	  // $ref->{dep_platform};
	$ref->{sched_departure_platform} = $ref->{dep_platform};

	# {has_realtime} = rt?

	return bless( $ref, $obj );
}

sub arrival_time {
	my ($self) = @_;

	return $self->arrival_datetime->strftime('%H:%M');
}

sub arrival_stop_and_platform {
	my ($self) = @_;

	if ( $self->{arrival_platform} ) {
		return
		  sprintf( '%s: %s', $self->{arrival_stop}, $self->{arrival_platform} );
	}

	return $self->{arrival_stop};
}

sub departure_time {
	my ($self) = @_;

	return $self->departure_datetime->strftime('%H:%M');
}

sub departure_stop_and_platform {
	my ($self) = @_;

	if ( $self->{departure_platform} ) {
		return sprintf( '%s: %s',
			$self->{departure_stop},
			$self->{departure_platform} );
	}

	return $self->{departure_stop};
}

sub sched_arrival_time {
	my ($self) = @_;

	return $self->sched_arrival_datetime->strftime('%H:%M');
}

sub sched_departure_time {
	my ($self) = @_;

	return $self->sched_departure_datetime->strftime('%H:%M');
}

sub comments {
	my ($self) = @_;

	if ( exists $self->{comments} ) {
		return @{ $self->{comments} };
	}
	return;
}

sub TO_JSON {
	my ($self) = @_;

	return { %{$self} };
}

sub type {
	my ($self) = @_;

	# $self->{train} is either "TYPE 12345" or "TYPE12345"
	my ($type) = ( $self->{line} =~ m{ ^ ([A-Z]+) }x );

	return $type;
}

1;

__END__

=head1 NAME

Travel::Status::DE::HAFAS::Result - Information about a single
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

Travel::Status::DE::HAFAS::Result describes a single arrival/departure
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
