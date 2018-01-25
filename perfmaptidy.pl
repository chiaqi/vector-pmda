#!/usr/bin/perl
#
# perfmaptidy.pl - tidy up a Linux perf_events /tmp/perf-%d.map file.
#
# Linux perf_events can mis-translate symbols when the map file has grown
# dynamically, and includes stale entries. perfmaptidy.pl reads such a symbol
# table, then replays the mappings backwards, dropping overlaps. It then emits
# tidy symbol table, containing only the most recent mappings.
#
# USAGE: ./perfmaptidy.pl /tmp/perf-1572.livemap > /tmp/perf-1572.map
#
# For this to work, you would want your JIT agent to write to a different
# file than usual (eg, ".livemap"), so that perfmaptidy.pl can turn it into
# the ".map" file that perf expects. Or, you can use mv to rename the live .map
# file to be a .livemap file, and then recreate the .map file using
# perfmaptidy.pl (the new .livemap file should continue being written to).
#
# Copyright 2017 Netflix, Inc.
# Licensed under the Apache License, Version 2.0 (the "License")

use strict;
# no warnings, to avoid non-portable warnings when reading large ints
# without BigInt (which is slow)

my @table;		# map table

sub store {
	my ($addr, $size, $symbol) = @_;
	my $low = 0;
	my $high = $#table;
	my $mid;

	# binary search
	while ($low <= $high) {
		$mid = int(($low + $high) / 2);
		if ($addr >= $table[$mid]->{start} && $addr <= $table[$mid]->{end}) {
			return;
		} elsif ($addr < $table[$mid]->{start}) {
			$high = $mid - 1;
		} else {
			$low = $mid + 1;
		}
	}

	# check for latter overlaps
	if ($#table >= 0 and defined $table[$high + 1]) {
		my $next = $table[$high + 1]->{start};
		if ($next >= $addr && $next <= $addr + $size) {
			return;
		}
	}

	# store
	my $data = {};
	$data->{start} = $addr;
	$data->{end} = $addr + $size;
	$data->{symbol} = $symbol;
	splice @table, $low, 0, $data;
}

# load map file from STDIN
my @symbols = <>;
for (my $i = $#symbols; $i >= 0; $i--) {
	my ($addr, $size, $symbol) = split ' ', $symbols[$i], 3;
	chomp $symbol;
	store(hex($addr), hex($size), $symbol);
}

# emit map file on STDOUT
for (my $i = 0; $i <= $#table; $i++) {
	my $size = $table[$i]->{end} - $table[$i]->{start};
	printf "%x %x %s\n", $table[$i]->{start}, $size, $table[$i]->{symbol};
}
