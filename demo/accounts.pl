#! /usr/local/bin/perl

use lib qw(../lib);
use Finance::Bank::Commonwealth();
use strict;

eval {
	my ($bank) = new Finance::Bank::Commonwealth({	
					'login'		=> 'xxx',
					'password'	=> 'yyy',
					'user_agent'	=> 'Finance::Bank::Commonwealth',
							});

	my ($account);
	$account = new Finance::Bank::Commonwealth::Account({
						'bsb' => 'xxxx',
						'number' => 'yyyy',
						'type' => 'Streamline'
							});

	print "---------------------------------------------\n";
	foreach $account ($bank->accounts()) {
		print "Account Id: ". $account->id() . "\n";
		print "Account Code: ". $account->code() . "\n";
		print "Account BSB: " . $account->bsb() . "\n";
		print "Account Number: " . $account->number() . "\n";
		print "Account Name: " . $account->name() . "\n";
		print "Account Type: " . $account->type() . "\n";
		print "Account Balance: " . $account->balance() . "\n";
		print "Available Funds: " . $account->available() . "\n";
		print "---------------------------------------------\n";
	}
};
if ($@) {
	print "$@";
}
