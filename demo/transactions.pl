#! /usr/local/bin/perl

use lib qw(../lib);
use Finance::Bank::Commonwealth();
use strict;

eval {
	my ($bank) = new Finance::Bank::Commonwealth({	
					'login'		=> 'xxx',
					'password'	=> 'yyy'
							});

	my ($account) = new Finance::Bank::Commonwealth::Account({
					'bsb' => 'xxx',
					'number' => 'yyy',
					'type' => 'Streamline'
						});

	my ($transaction);
	print "-----------------------------------\n";
	foreach $transaction ($bank->transactions($account)) {
		print "Transaction Date: " . $transaction->date() . "\n";
		print "Transaction Reason: " . $transaction->reason() . "\n";
		print "Transaction Amount: " . $transaction->amount() . "\n";
		print "Transaction Total: " . $transaction->total() . "\n";
		print "-----------------------------------\n";
	}
};
if ($@) {
	print "$@";
}
