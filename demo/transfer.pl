#! /usr/local/bin/perl

use Finance::Bank::Commonwealth();
use strict;

my ($limit) = 5000; # Credit Card Limit

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

	my ($to);
	my ($account);
	foreach $account ($bank->accounts()) {
		if ($account->type() eq 'MasterCard') {
			$to = $account;
		}
	}

	if ($to->available() < $limit) { # If the MasterCard has been used.
		my ($amount) = $limit - $to->available();
		my ($success) = $bank->transfer($from, $to, $amount, "50 Days");
		if ($success) {
			print "Date:" . $success->date() . "\n";
			print "Time:" . $success->time() . "\n";
			print "Receipt Number:" . $success->receipt_number() . "\n";
		}
	}
};
if ($@) {
	print "$@";
}
