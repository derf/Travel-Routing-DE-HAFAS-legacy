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
	my $date = $conf{date} // strftime( '%d.%m.%Y', localtime(time) );
	my $time = $conf{time} // strftime( '%H:%M',    localtime(time) );

	my %lwp_options = %{ $conf{lwp_options} // { timeout => 10 } };

	my $ua = LWP::UserAgent->new(%lwp_options);

	$ua->env_proxy;

	my $reply;

	my $lang = $conf{language} // 'd';

	if ( not $conf{from} or not $conf{to} ) {
		confess('You need to specify a station');
	}

	my $ref = {};

	bless( $ref, $obj );
	$reply
	  = $ua->post( "http://reiseauskunft.bahn.de/bin/query.exe/${lang}n"
		  . '?start=Suchen&S='
		  . $conf{from} . '&Z='
		  . $conf{to}
		  . '&REQ0HafasSearchForw=1'
		  . "&REQ0JourneyDate=$date&REQ0JourneyTime=$time"
		  . '&REQ0JourneyProduct_prod_list_1=11111111111111&h2g-direct=11'
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

sub extract_at {
	my ( $self, $pos, $template ) = @_;

	return unpack( 'x' . $pos . $template, $self->{reply} );
}

sub extract_str {
	my ( $self, $ptr ) = @_;

	$ptr += $self->{offset}{strtable};

	return unpack( 'x' . $ptr . 'Z*', $self->{reply} );
}

sub parse_extensions {
	my ($self) = @_;

	my (
		$len,         $unk1,          $seqnr, $reqid_ptr,
		$details_ptr, $err,           $unk2,  $enc_ptr,
		$unk_ptr,     $attrib_offset, $attrib_pos
	  )
	  = $self->extract_at( $self->{offset}{extensions},
		'L L S S L S H28 S S S L' );

	printf( "extlen %d\n",               $len );
	printf( "unk1 %d\n",                 $unk1 );
	printf( "seqnr %d\n",                $seqnr );
	printf( "reqid %s\n",                $self->extract_str($reqid_ptr) );
	printf( "details_ptr %d\n",          $details_ptr );
	printf( "error %d\n",                $err );
	printf( "unk2 %s\n",                 $unk2 );
	printf( "enc %s\n",                  $self->extract_str($enc_ptr) );
	printf( "??? %s\n",                  $self->extract_str($unk_ptr) );
	printf( "attr offset/pos %d / %d\n", $attrib_offset, $attrib_pos );

	$self->{offset}{details}     = $details_ptr;
	$self->{offset}{attributes1} = $attrib_offset;
	$self->{offset}{attributes2} = $attrib_pos;
}

sub parse_details {
	my ($self) = @_;

	my $detail_ptr = $self->{offset}{details};

	my ( $version, $unk, $detail_index_off, $detail_part_off, $detail_part_size,
		$stop_size, $stop_off )
	  = $self->extract_at( $detail_ptr, 'S S S S S S S' );

	printf( "detailhdr version %d\n",   $version );
	printf( "detailhdr unk %d\n",       $unk );
	printf( "detailhdr index ptr %d\n", $detail_index_off );
	printf( "detailhdr part ptr %d\n",  $detail_part_off );
	printf( "detailhdr part size %d\n", $detail_part_size );
	printf( "detailhdr stop size %d\n", $stop_size );
	printf( "detailhdr stop ptr %d\n",  $stop_off );

	$self->{offset}{detail_index} = $detail_ptr + $detail_index_off;
	$self->{offset}{part_index}   = $detail_ptr + $detail_part_off;
	$self->{offset}{stop_index}   = $detail_ptr + $stop_off;
}

sub parse_station {
	my ( $self, $st_offset ) = @_;

	my $ptr = $self->{offset}{stations} + ( 14 * $st_offset );

	my ( $name_ptr, $stopid, $lon, $lat )
	  = $self->extract_at( $ptr, 'S L L L' );
	my $station_name = $self->extract_str($name_ptr);

	printf( "- name %s\n",     $station_name );
	printf( "- id %d\n",       $stopid );
	printf( "- pos %f / %f\n", $lon / 1_000_000, $lat / 1_000_000 );
}

sub parse_comments {
	my ( $self, $com_offset ) = @_;

	my $num_comments
	  = $self->extract_at( $self->{offset}{comments} + $com_offset, 'S' );
	my @comment_ptrs
	  = $self->extract_at( $self->{offset}{comments} + $com_offset + 2,
		'S' x $num_comments );
	for my $ptr (@comment_ptrs) {
		printf( "comment %s\n", $self->extract_str($ptr) );
	}
}

sub parse_attributes {
	my ( $self, $attr_offset ) = @_;

	my $ptr = $self->{offset}{attributes1} + ( 4 * $attr_offset );

	while ( $self->extract_at( $ptr, 'S' ) != 0 ) {
		my ( $key_ptr, $value_ptr ) = $self->extract_at( $ptr, 'S S' );
		printf( "- attr %s: %s\n",
			$self->extract_str($key_ptr),
			$self->extract_str($value_ptr) );
		$ptr += 4;
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

sub parse_part_details {
	my ( $self, $detail_ptr, $partno ) = @_;

	my $ptr = $self->{offset}{part_index} + $detail_ptr + ( 16 * $partno );

	my ( $dep_time, $arr_time, $dep_platform_ptr, $arr_platform_ptr,
		$unk, $stop_idx, $num_stops )
	  = $self->extract_at( $ptr, 'S S S S L S S' );

	printf( "- rt dep %d (%s)\n",
		$dep_time, $self->extract_str($dep_platform_ptr) );
	printf( "- rt arr %d (%s)\n",
		$arr_time, $self->extract_str($arr_platform_ptr) );
	printf( "- num intermediate stops %d (first %d)\n", $num_stops, $stop_idx );

	for my $i ( 0 .. $num_stops - 1 ) {
		$self->parse_stop( $stop_idx, $i );
	}
}

sub parse_stop {
	my ( $self, $stop_idx, $num_stop ) = @_;
	my $ptr = $self->{offset}{stop_index} + ( 26 * ( $stop_idx + $num_stop ) );

	my (
		$s_dep_time,         $s_arr_time,          $s_dep_platform_ptr,
		$s_arr_platform_ptr, $s_unk,               $rt_dep_time,
		$rt_arr_time,        $rt_dep_platform_ptr, $rt_arr_platform_ptr,
		$rt_unk,             $station_ptr
	) = $self->extract_at( $ptr, 'S S S S L S S S S L S' );

	$self->parse_station($station_ptr);
	printf(
		"-- sched: arr %d (%s), dep %d (%s), unk %d\n",
		$s_arr_time, $self->extract_str($s_arr_platform_ptr),
		$s_dep_time, $self->extract_str($s_dep_platform_ptr), $s_unk
	);
	printf(
		"-- rt: arr %d (%s), dep %d (%s), unk %d\n",
		$rt_arr_time, $self->extract_str($rt_arr_platform_ptr),
		$rt_dep_time, $self->extract_str($rt_dep_platform_ptr), $rt_unk
	);
}

sub parse_journey {
	my ( $self, $num ) = @_;

	my $ptr = 0x4a + ( 12 * $num );

	my ( $service_days_offset, $parts_offset, $num_parts, $num_changes, $unk )
	  = $self->extract_at( $ptr, 'S L S S S' );

	printf( "Journey %d: off 0x%x/0x%x, %d parts, %d changes, unk %d\n",
		$num + 1, $service_days_offset, $parts_offset, $num_parts,
		$num_changes, $unk );

	$self->{offset}{journeys}[$num]{service_days}
	  = $self->{offset}{servicedays} + $service_days_offset;
	$self->{offset}{journeys}[$num]{parts} = $parts_offset + 0x4a;
	$self->{journeys}[$num]{num_parts}     = $num_parts;
	$self->{journeys}[$num]{num_changes}   = $num_changes;

	my $svcd_ptr = $self->{offset}{journeys}[$num]{service_days};
	my $desc_ptr = $self->extract_at( $svcd_ptr, 'S' );
	printf( "Service days: %s\n", $self->extract_str($desc_ptr) );

	my $detail_ptr
	  = $self->extract_at( $self->{offset}{detail_index} + ( 2 * $num ), 'S' );
	printf( "detail ptr %d\n", $detail_ptr );

	my ( $rts, $delay )
	  = $self->extract_at( $self->{offset}{details} + $detail_ptr, 'S S' );
	printf( "rts %d\n",   $rts );
	printf( "delay %d\n", $delay );

	for my $i ( 0 .. $self->{journeys}[$num]{num_parts} - 1 ) {
		my (
			$dep_time,   $dep_station, $arr_time,     $arr_station,
			$type,       $line,        $dep_platform, $arr_platform,
			$attrib_ptr, $comments_ptr
		  )
		  = $self->extract_at(
			$self->{offset}{journeys}[$num]{parts} + ( 20 * $i ),
			'S S S S S S S S S S' );

		printf( "\n- dep %d (%s)\n",
			$dep_time, $self->extract_str($dep_platform) );
		$self->parse_station($dep_station);
		printf( "- arr %d (%s)\n",
			$arr_time, $self->extract_str($arr_platform) );
		$self->parse_station($arr_station);
		printf( "- line %s\n", $self->extract_str($line) );
		$self->parse_attributes($attrib_ptr);
		$self->parse_comments($comments_ptr);
		$self->parse_part_details( $detail_ptr, $i );
	}
}

sub parse_header {
	my ($self) = @_;

	my $data = $self->{reply};

	my (
		$version,     $origin,     $destination, $numjourneys, $svcdayptr,
		$strtableptr, $date,       $unk1,        $unk2,        $unk3,
		$stationptr,  $commentptr, $unk4,        $extptr
	) = unpack( 'S A14 A14 S L L S S S A8 L L A8 L', $data );

	my (
		$hversion,   $horigin,      $hdestination, $hnumjourneys,
		$hsvcdayptr, $hstrtableptr, $hdate,        $hunk1,
		$hunk2,      $hunk3,        $hstationptr,  $hcommentptr,
		$hunk4,      $hextptr
	) = unpack( 'H4 H28 H28 H4 H8 H8 H4 H4 H4 H16 H8 H8 H16 H8', $data );

	say unpack( 'H' . ( 2 * 0x4a ), $data );

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
	printf( "unk4: (%s)\n",                     $hunk4 );
	printf( "extension offset: 0x%x (%s)\n",    $extptr,      $hextptr );

	return $numjourneys;
}

sub results {
	my ($self) = @_;

	my $numjourneys = $self->parse_header;
	$self->parse_extensions;
	$self->parse_details;

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
