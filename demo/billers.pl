#! /usr/local/bin/perl

use lib qw(../lib);
use Finance::Bank::Commonwealth();
use strict;

eval { 
	my ($bank) = new Finance::Bank::Commonwealth({	
					'login'		=> 'xxx',
					'password'	=> 'yyy',
							});

	print "---------------------------------------------\n";
	my ($biller);
	foreach $biller ($bank->billers()) {
		print "Biller Id: " . $biller->id() . "\n";
		print "Biller Code: " . $biller->code() . "\n";
		print "Biller Name: " . $biller->name() . "\n";
		print "Customer Reference No.: " . $biller->customer_ref_no() . "\n";
		print "---------------------------------------------\n";
	}
};
if ($@) {
	print $@;
}
