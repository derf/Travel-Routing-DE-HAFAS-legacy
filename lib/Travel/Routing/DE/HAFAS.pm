package Travel::Routing::DE::HAFAS;

use strict;
use warnings;
use 5.010;

no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp qw(confess);
use LWP::UserAgent;
use POSIX qw(strftime);
use Travel::Routing::DE::HAFAS::Result;
use IO::Uncompress::Gunzip qw(gunzip);

our $VERSION = '0.00';

sub new {
	my ( $obj, %conf ) = @_;
	my $date = strftime( '%d.%m.%Y', localtime(time) );
	my $time = strftime( '%H:%M',    localtime(time) );

	my %lwp_options = %{ $conf{lwp_options} // { timeout => 10 } };

	my $ua = LWP::UserAgent->new(%lwp_options);

	$ua->env_proxy;

	my $reply;

	my $lang = $conf{language} // 'd';

	if ( not $conf{from} or not $conf{to} ) {
		confess('You need to specify a station');
	}

	my $ref = {
		mot_filter => [
			$conf{mot}->{ice}   // 1,
			$conf{mot}->{ic_ec} // 1,
			$conf{mot}->{d}     // 1,
			$conf{mot}->{nv}    // 1,
			$conf{mot}->{s}     // 1,
			$conf{mot}->{bus}   // 0,
			$conf{mot}->{ferry} // 0,
			$conf{mot}->{u}     // 0,
			$conf{mot}->{tram}  // 0,
		],
		post => {
			productsFilter => '11111111111111',
			input          => $conf{station},
			date           => $conf{date} || $date,
			time           => $conf{time} || $time,
			start          => 'yes',
			boardType      => $conf{mode} // 'dep',
			L              => 'vs_java3',
		},
	};

	bless( $ref, $obj );
	$reply
	  = $ua->post( "http://reiseauskunft.bahn.de/bin/query.exe/${lang}n"
		  . '?start=Suchen&S='
		  . $conf{from} . '&Z='
		  . $conf{to}
		  . '&REQ0HafasSearchForw=1'
		  . '&REQ0JourneyDate=26.08.15&REQ0JourneyTime=12%3A05'
		  . '&REQ0JourneyProduct_prod_list_1=11111111110000&h2g-direct=11'
		  . '&clientType=ANDROID' );

	if ( $reply->is_error ) {
		$ref->{errstr} = $reply->status_line;
		return $ref;
	}
	$ref->{raw_reply} = $reply->content;
	gunzip( \$ref->{raw_reply}, \$ref->{reply} );
	return $ref;
}

sub errstr {
	my ($self) = @_;

	return $self->{errstr};
}

sub extract_str {
	my ( $self, $ptr ) = @_;

	$ptr += $self->{offset}{strtable};

	return unpack( 'x' . $ptr . 'Z*', $self->{reply} );
}

sub parse_station {
	my ( $self, $st_offset ) = @_;

	my $ptr = $self->{offset}{stations} + ( 14 * $st_offset );

	my ( $name_ptr, $stopid, $lon, $lat )
	  = unpack( 'x' . $ptr . 'SLLL', $self->{reply} );
	my $station_name = $self->extract_str($name_ptr);

	printf( "- name %s\n",     $station_name );
	printf( "- id %d\n",       $stopid );
	printf( "- pos %f / %f\n", $lon / 1_000_000, $lat / 1_000_000 );
}

sub parse_comments {
	my ( $self, $com_offset ) = @_;

	my $num_comments
	  = unpack( 'x' . ( $self->{offset}{comments} + $com_offset ) . 'S',
		$self->{reply} );
	my @comment_ptrs = unpack(
		'x'
		  . ( $self->{offset}{comments} + $com_offset + 2 )
		  . 'S' x $num_comments,
		$self->{reply}
	);
	for my $ptr (@comment_ptrs) {
		printf( "comment %s\n", $self->extract_str($ptr) );
	}
}

sub parse_location {
	my ( $self, $data ) = @_;

	my ( $name_offset, $unk, $type, $lon, $lat ) = unpack( 'S S S L L', $data );
	printf(
		"Location: pos %d, unk %d, type %d, lon/lat %f %f\n",
		$name_offset, $unk, $type,
		$lon / 1_000_000,
		$lat / 1_000_000
	);

	printf( "Location name: %s\n", $self->extract_str($name_offset) );
	return ( $name_offset, $type, $lon, $lat );
}

sub parse_journey {
	my ( $self, $num ) = @_;

	my $ptr = 0x4a + ( 12 * $num );

	my ( $service_days_offset, $parts_offset, $num_parts, $num_changes, $unk )
	  = unpack( 'x' . $ptr . 'S L S S S', $self->{reply} );

	printf( "Journey %d: off 0x%x/0x%x, %d parts, %d changes, unk %d\n",
		$num + 1, $service_days_offset, $parts_offset, $num_parts,
		$num_changes, $unk );

	$self->{offset}{journeys}[$num]{service_days}
	  = $self->{offset}{servicedays} + $service_days_offset;
	$self->{offset}{journeys}[$num]{parts} = $parts_offset + 0x4a;
	$self->{journeys}[$num]{num_parts}     = $num_parts;
	$self->{journeys}[$num]{num_changes}   = $num_changes;

	my $svcd_ptr = $self->{offset}{journeys}[$num]{service_days};
	my $desc_ptr = unpack( 'x' . $svcd_ptr . 'S', $self->{reply} );
	printf( "Service days: %s\n", $self->extract_str($desc_ptr) );

	for my $i ( 0 .. $self->{journeys}[$num]{num_parts} - 1 ) {
		my (
			$dep_time,   $dep_station, $arr_time,     $arr_station,
			$type,       $line,        $dep_platform, $arr_platform,
			$attrib_ptr, $comments_ptr
		  )
		  = unpack(
			'x'
			  . ( $self->{offset}{journeys}[$num]{parts} + ( 20 * $i ) )
			  . 'S S S S S S S S S S',
			$self->{reply}
		  );

		printf( "\n- dep %d (%s)\n",
			$dep_time, $self->extract_str($dep_platform) );
		$self->parse_station($dep_station);
		printf( "- arr %d (%s)\n",
			$arr_time, $self->extract_str($arr_platform) );
		$self->parse_station($arr_station);
		printf( "- line %s\n", $self->extract_str($line) );
		$self->parse_comments($comments_ptr);
	}
}

sub results {
	my ($self) = @_;
	my $data = $self->{reply};

	my (
		$version,     $origin,     $destination, $numjourneys, $svcdayptr,
		$strtableptr, $date,       $unk1,        $unk2,        $unk3,
		$stationptr,  $commentptr, $unk4,        $extptr
	) = unpack( 'S A14 A14 S L L S S S A8 L L S L', $data );

	my (
		$hversion,   $horigin,      $hdestination, $hnumjourneys,
		$hsvcdayptr, $hstrtableptr, $hdate,        $hunk1,
		$hunk2,      $hunk3,        $hstationptr,  $hcommentptr,
		$hunk4,      $hextptr
	) = unpack( 'H4 H28 H28 H4 H8 H8 H4 H4 H4 H16 H8 H8 H4 H8', $data );

	$self->{offset}{servicedays} = $svcdayptr;
	$self->{offset}{strtable}    = $strtableptr;
	$self->{offset}{stations}    = $stationptr;
	$self->{offset}{comments}    = $commentptr;
	$self->{offset}{extensions}  = $extptr;

	printf( "Version: %d (%s)\n", $version, $hversion );
	printf( "Origin: (%s)\n", $horigin );
	my ($orig_name_pos) = $self->parse_location($origin);
	printf( "Dest: (%s)\n", $hdestination );
	my ($dest_name_pos) = $self->parse_location($destination);
	printf( "num journeys: %d (%s)\n",          $numjourneys, $hnumjourneys );
	printf( "service days offset: 0x%x (%s)\n", $svcdayptr,   $hsvcdayptr );
	printf( "string table offset: 0x%x (%s)\n", $strtableptr, $hstrtableptr );
	printf( "date: %d (%s)\n",                  $date,        $hdate );
	printf( "unk1: %d (%s)\n",                  $unk1,        $hunk1 );
	printf( "unk2: %d (%s)\n",                  $unk2,        $hunk2 );
	printf( "unk3: (%s)\n",                     $hunk3 );
	printf( "stations offset: 0x%x (%s)\n",     $stationptr,  $hstationptr );
	printf( "comments offset: 0x%x (%s)\n",     $commentptr,  $hcommentptr );
	printf( "unk4: %d (%s)\n",                  $unk4,        $hunk4 );
	printf( "extension offset: 0x%x (%s)\n",    $extptr,      $hextptr );

	for my $i ( 0 .. $numjourneys - 1 ) {
		print "\n";
		$self->parse_journey($i);
	}

	#	say $self->{reply};
}

1;

__END__

=head1 NAME

Travel::Status::DE::HAFAS - Interface to HAFAS-based online arrival/departure
monitors

=head1 SYNOPSIS

	use Travel::Status::DE::HAFAS;

	my $status = Travel::Status::DE::HAFAS->new(
		station => 'Essen Hbf',
	);

	if (my $err = $status->errstr) {
		die("Request error: ${err}\n");
	}

	for my $departure ($status->results) {
		printf(
			"At %s: %s to %s from platform %s\n",
			$departure->time,
			$departure->line,
			$departure->destination,
			$departure->platform,
		);
	}

=head1 VERSION

version 0.00

=head1 DESCRIPTION

Travel::Status::DE::HAFAS is an interface to HAFAS-based
arrival/departure monitors, for instance the one available at
L<http://reiseauskunft.bahn.de/bin/bhftafel.exe/dn>.

It takes a station name and (optional) date and time and reports all arrivals
or departures at that station starting at the specified point in time (now if
unspecified).

=head1 METHODS

=over

=item my $status = Travel::Status::DE::HAFAS->new(I<%opts>)

Requests the departures/arrivals as specified by I<opts> and returns a new
Travel::Status::DE::HAFAS element with the results.  Dies if the wrong
I<opts> were passed.

Supported I<opts> are:

=over

=item B<station> => I<station>

The train station to report for, e.g.  "Essen HBf" or
"Alfredusbad, Essen (Ruhr)".  Mandatory.

=item B<date> => I<dd>.I<mm>.I<yyyy>

Date to report for.  Defaults to the current day.

=item B<language> => I<language>

Set language for additional information. Accepted arguments: B<d>eutsch,
B<e>nglish, B<i>talian, B<n> (dutch).

=item B<lwp_options> => I<\%hashref>

Passed on to C<< LWP::UserAgent->new >>. Defaults to C<< { timeout => 10 } >>,
you can use an empty hashref to override it.

=item B<time> => I<hh>:I<mm>

Time to report for.  Defaults to now.

=item B<mode> => B<arr>|B<dep>

By default, Travel::Status::DE::HAFAS reports train departures
(B<dep>).  Set this to B<arr> to get arrivals instead.

=item B<mot> => I<\%hashref>

Modes of transport to show.  Accepted keys are: B<ice> (ICE trains), B<ic_ec>
(IC and EC trains), B<d> (InterRegio and similarly fast trains), B<nv>
("Nahverkehr", mostly RegionalExpress trains), B<s> ("S-Bahn"), B<bus>,
B<ferry>, B<u> ("U-Bahn") and B<tram>.

Setting a mode (as hash key) to 1 includes it, 0 excludes it.  undef leaves it
at the default.

By default, the following are shown: ice, ic_ec, d, nv, s.

=back

=item $status->errstr

In case of an error in the HTTP request, returns a string describing it.  If
no error occurred, returns undef.

=item $status->results

Returns a list of arrivals/departures.  Each list element is a
Travel::Status::DE::HAFAS::Result(3pm) object.

If no matching results were found or the parser / http request failed, returns
undef.

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item * Class::Accessor(3pm)

=item * LWP::UserAgent(3pm)

=item * XML::LibXML(3pm)

=back

=head1 BUGS AND LIMITATIONS

There are a few character encoding issues.

=head1 SEE ALSO

Travel::Status::DE::HAFAS::Result(3pm).

=head1 AUTHOR

Copyright (C) 2011 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
