#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

Module::Build->new(

	build_requires => {
		'Test::More'    => 0,
		'Test::Compile' => 0,
		'Test::Pod'     => 0,
	},
	configure_requires => {
		'Module::Build' => 0.40,
	},
	module_name => 'Travel::Routing::DE::HAFAS',
	license     => 'perl',
	requires    => {
		'perl'            => '5.10.1',
		'Carp'            => 0,
		'Class::Accessor' => '0.16',
		'DateTime'        => 0,
		'Getopt::Long'    => 0,
		'IO::Uncompress::Gunzip' => 0,
		'List::Util'      => 0,
		'LWP::UserAgent'  => 0,
		'POSIX'           => 0,
	},
	script_files => 'bin/',
	sign         => 1,

)->create_build_script();
