#! /usr/local/bin/perl

use lib qw(../lib);
use Finance::Bank::Commonwealth();
use strict;

eval {
	my ($bank) = new Finance::Bank::Commonwealth({	
					'login'		=> 'xxx',
					'password'	=> 'yyy'
							});

	my ($from) = new Finance::Bank::Commonwealth::Account({
					'bsb' => 'xxx',
					'number' => 'yyy',
					'type' => 'Streamline'
						});

	my ($biller) = new Finance::Bank::Commonwealth::Biller({ 
					'code' => 'xxx',
					'ref_no' => 'yyy' });

	my ($success) = $bank->bpay($from, $biller, 24.95);
	if ($success) {
		print "Date:" . $success->date() . "\n";
		print "Time:" . $success->time() . "\n";
		print "Receipt Number:" . $success->receipt_number() . "\n";
	}
};
if ($@) {
	print "$@";
}
