package Finance::Bank::Commonwealth;
use strict;

BEGIN {
	use LWP();
	use Net::SSLeay();
	use vars qw($VERSION $debug);
	$debug = 0;
	$VERSION = 0.99;
}

my ($defaultUserAgent) = 'Finance::Bank::Commonwealth.pm';

=head1 NAME

Finance::Bank::Commonwealth - Front-end module to netbank.com.au

=head1 SYNOPSIS

  use Finance::Bank::Commonwealth();

  my ($bank) = new Finance::Bank::Commonwealth({
                        'login' => 'xxxx',
                        'password' => 'yyy'
                                 });

  my ($from);
  print "----------------------\n";
  foreach $account ($bank->accounts()) {
      print "Account Id: ". $account->id() . "\n";
      print "Account Code: ". $account->code() . "\n";
      print "Account BSB: " . $account->bsb() . "\n";
      print "Account Number: " . $account->number() . "\n";
      print "Account Name: " . $account->name() . "\n";
      print "Account Type: " . $account->type() . "\n";
      print "Account Balance: " . $account->balance() . "\n";
      print "Available Funds: " . $account->available() ."\n";
      print "----------------------\n";
      if ($account->type() eq 'MasterCard') {
          $from = $account;
      }        
  }

  my ($to) = new Finance::Bank::Commonwealth::Account({
                    'bsb'           => '654321',
                    'number'        => '12345678',
                    'type'          => 'BankAccount',
                    'name'          => 'Bob\'s Account',
                                });

  my ($success) = $bank->transfer($from, $to, 1.50, "Why?");
  if ($success) {
      print "Date:" . $success->{'date'} . "\n";
      print "Time:" . $success->{'time'} . "\n";
      print "Receipt Number:" . $success->{'receipt_number'} . "\n";
  }

=head1 DESCRIPTION

Attention!!!! This module gets access to YOUR MONEY!!!!!! DO NOT USE IT unless you are comfortable with the notion that you could (in theory) completely bugger your accounts if the Commonwealth Bank changed their website significantly.  DO NOT USE IT unless you have inspected the code and feel comfortable with it.  DO NOT come crying to me if it all goes horribly wrong.  This is intended as a demonstration module, NOT as a production worthy system.

*ahem* Now that i've done everything possible to ensure that this module is never used, on with the show.

This module provides an API to the Commonwealth Bank's netbank.com.au website.  It translates the method calls into http(s) requests.  Due to the fragile nature of this type of API (due to the probability that the EDS may attempt to change the implementation and hence break this API), this module is NOT recommended for mission critical applications.  Rather, it is intended for more casual uses.  It is also worth noting that if you give this module your id and password, you are letting the module do whatever it wants with YOUR MONEY!!! This means that unless you competent at Perl and can read and understand this module, you would be well advised not to use it.

Also, because if the module fails to parse anything successfully, it will throw an exception.  Any section of code that uses this module should be wrapped in an eval type structure (such as Graham Barrs Error module).

=head1 PARSING NOTES

The architects working on the Commonwealth Bank's website seem to have made a number of design decisions which I will document here to make it easier to understand what the HTML is doing.  

1) They decided to not use cookies, rather to use special hidden form fields (EWF_SYS_0 & EWF_SYS_1) to record session state.  Also, they decided to use a dynamic URL, so that someone must track through all the pages in a sequence.

2) They decided to obfuscate using simple javascript for the most part, and html redirects and frames during the initial loads.

3) Javascript obfuscation consists of just escaping the page and placing it in a javascript string.

4) Obfuscation is usually dispensed with after the first couple of screens in a sequence. 

5) Session state is often only recorded on the server, meaning that you don't actually see confirmation in the form fields of what is happening.

=head1 METHODS

=head2 new(\%params)

The new constructor instantiates a new Bank object.  It attempts
to log onto the netbank.com.au site using the login and password 
provided in the params hash

  my ($bank) = new Finance::Bank::Commonwealth({ 
                        'login' => 'xxx', 
                        'password' => 'yyy',
                        'user_agent' => 'Finance::Bank::Commonwealth',
                                });

A reference to the bank object is returned that can be used to 
access the instance methods for this class.

=cut

sub new {
	my ($proto, $params) = @_;
	my ($class) = ref($proto) || $proto;
	my ($self) = {};
	unless (($params->{'login'}) && ($params->{'password'})) {
		die "A login and password must be supplied";
	}
	bless $self, $class;
	$self->{'accounts'} = [];
	$self->{'user_agent'} = $params->{'user_agent'} || $defaultUserAgent;
	my ($page) = $self->_get('http://www.netbank.commbank.com.au/netbank');
	if ($page =~ m#CONTENT="0; URL=(.*?)"#isg) {
		my ($redirect) = $1;
		$page = $self->_get($redirect);
		if ($page =~ m#ACTION="(.*?)"#) {
			my ($postRedirect) = $1;
			my ($fields);
			while ($page =~ m#INPUT TYPE="?HIDDEN"? name="(.*?)" value="(.*?)"#isg) {
				$fields->{$1} = $2;
			}
			my ($requiredFields) = {	'EWFBUTTON'	=> '', 
							'LANGUAGE ID'	=> '',
							'PIN' => '',
							'EWF_SYS_0' => undef,
							'BANK ID' => 'CBA',
							'PRODUCT NAME' => 'EBS',
							'EWF_FORM_NAME' => 'aBegin',
							'USERID' => '',
							'GROUP' => 'BANKING',
						};
			$self->_checkFields($fields, $requiredFields);
			$page = $self->_post($postRedirect, $fields);
#
# The following pattern match and possible substitution are necessary because of bad code management by EDS.  Hopefully, this will be fixed, sometime soon... 
#
			if ($page =~ m#<FORM.*?FORM>.*?<FORM.*?FORM>#is) {
				$page =~ s#<FORM.*?FORM>##is;  # There are two forms on this page, only submit the second
			}
			if ($page =~ m#ACTION="(.*?)"#) {
				my ($url) = $1;
				$fields = {};
				while ($page =~ m#INPUT TYPE="?HIDDEN"? name="(.*?)" value="(.*?)"#isg) {
					$fields->{$1} = $2;
				}	
				$fields->{'LOGONID'} = $params->{'login'};
				$fields->{'USERID'} = $params->{'login'};
				$fields->{'PASSWORD'} = $params->{'password'};
				$fields->{'PIN'} = $params->{'password'};
				my ($mainScreen) = $self->_post($url, $fields);
				if ($mainScreen =~ m#timeout.htm#) {
					die "Bank timed out";
				} elsif ($mainScreen =~ m#The Client Number or Password entered is not valid#) {
					die "Login Failed";
				}
				$self->_parse_accounts($mainScreen);
				if ($mainScreen =~ m#function groupFunc(.*?)function mainFunc#is) {
					my ($html) = $1;
					if ($html =~ m#FORM TARGET="main" METHOD="POST" ACTION="(.*?)" NAME="APPS_FORM_GROUP"#) {
						$self->{'get_billing_info'}->{'url'} = $1;
						$self->{'get_billing_info'}->{'fields'} = {};
						while ($html =~ m#input type="?hidden"? name="(.*?)" value="(.*?)"#isg) {
							$self->{'get_billing_info'}->{'fields'}->{$1} = $2;
						}
						my ($requiredFields) = {	'EWFBUTTON' => '',
										'EWF_SYS_0' => undef,
										'EWF_SYS_1' => undef,
										'EWF_FORM_NAME' => 'MAIN Group Menu',
									};
						$self->_checkFields($self->{'get_billing_info'}->{'fields'}, $requiredFields);
						if ($html =~ m#Script:SubmitEBS\(\\\'GROUP-PAYBILLS\\\', \\\'EWF_BUTTON_PAYBILLS\\\'\);" onMous#s) {
							$self->{'get_billing_info'}->{'fields'}->{'EWF_BUTTON_GROUP-PAYBILLS'} = 'GROUP-PAYBILLS';
						} else {
							die "Failed to parse main screen for Billing Info";
						}
					} else {
						die "Failed to parse main screen for Billing Info";
					}
				} else {
					die "Failed to parse main screen for Billing Info";
				}
				if ($mainScreen =~ m#function groupFunc(.*?)function mainFunc#is) {
					my ($html) = $1;
					if ($html =~ m#FORM TARGET="main" METHOD="POST" ACTION="(.*?)" NAME="APPS_FORM_GROUP"#) {
						$self->{'transfer'}->{'url'} = $1;
						while ($html =~ m#input type="?hidden"?.*?name="(.*?)".*?value="(.*?)"#isg) {
							$self->{'transfer'}->{'fields'}->{$1} = $2;
						}
						while ($html =~ m#input type="?text"?.*?name="(.*?)".*?value="(.*?)"#isg) {
							$self->{'transfer'}->{'fields'}->{$1} = $2;
						}
						if ($html =~ m#Script:SubmitEBS\(\\\'GROUP-TRANSFERMONEY\\\', \\\'EWF_BUTTON_TRANSFERMONEY\\\'\);" onMous#s) {
							$self->{'transfer'}->{'fields'}->{'EWF_BUTTON_GROUP-TRANSFERMONEY'} = 'GROUP-TRANSFERMONEY';
						} else {
							die "Failed to parse main screen for Transfer Info";
						}
					} else {
						die "Failed to parse main screen for Transfer Info";
					}
				} else {
					die "Failed to parse main screen for Transfer Info";
				}
				if ($mainScreen =~ m#function groupFunc(.*?)function mainFunc#is) {
					my ($html) = $1;
					if ($html =~ m#FORM TARGET="main" METHOD="POST" ACTION="(.*?)" NAME="APPS_FORM_GROUP"#) {
						$self->{'get_accounts'}->{'url'} = $1;
						while ($html =~ m#input type="?hidden"?.*?name="(.*?)".*?value="(.*?)"#isg) {
							$self->{'get_accounts'}->{'fields'}->{$1} = $2;
						}
						while ($html =~ m#input type="?text"?.*?name="(.*?)".*?value="(.*?)"#isg) {
							$self->{'get_accounts'}->{'fields'}->{$1} = $2;
						}
						if ($html =~ m#Script:SubmitEBS\(\\\'GROUP-BANKING\\\', \\\'EWF_BUTTON_BANKING\\\'\);" onMous#s) {
							$self->{'get_accounts'}->{'fields'}->{'EWF_BUTTON_GROUP-BANKING'} = 'GROUP-BANKING';
						} else {
							die "Failed to parse main screen for Accounts Info";
						}
					} else {
						die "Failed to parse main screen for Accounts Info";
					}
				} else {
					die "Failed to parse main screen for Accounts Info";
				}
			} else {
				die "Failed to parse redirect to main screen";
			}
		} else {
			die "Failed to parse https redirect";
		}
	} else {
		die "Failed to parse html redirect";
	}
	return ($self);
}

=head2 billers

The billers method returns an array of all the 
Finance::Bank::Commonwealth::Biller objects that are currently connected
to the login.

  my ($biller);
  foreach $biller ($bank->billers()) {
      print "Biller Id: " . $biller->id() . "\n";
      print "Biller Code: " . $biller->code() . "\n";
      print "Biller Name: " . $biller->name() . "\n";
      print "Ref No.: " . $biller->customer_ref_no() . "\n";
  }

=cut

sub billers {
	my ($self) = @_;
	if ($self->{'get_billing_info'}->{'url'}) {
		my ($html) = $self->_post($self->{'get_billing_info'}->{'url'}, $self->{'get_billing_info'}->{'fields'});
		if ($html =~ m#var\s+aMAIN\s+=(.*?)$#is) {
			$html = $1;
			unless ($html =~ m#SELECT NAME="DATA1".*?Select an account.*?SELECT#is) {
				die "Failed to parse billers....\n";
			}
			while ($html =~ m#DATA2" VALUE="(.*?)".*?SIZE="2">0+(.*?)<BR>(.*?)</F.*?CRN.*?VALUE="(.*?)"#isg) {
				push @{$self->{'billers'}}, Finance::Bank::Commonwealth::Biller->new({ 
							'id' => $1,
							'code' => $2,
							'name' => $3,
							'ref_no' => $4,
							});
			}
		} else {
			die "Failed to parse billing page";
		}
	} else {
		die "Failed to obtain billing info from self";
	}
	return (@{$self->{'billers'}});
}

=head2 transfer($from, $to, $amount, $comment)

The transfer method transfers money from the $from account 
into the $to account.  The $from account MUST belong to the current
login. The method will return a Finance::Bank::Commonwealth::Success
object that gives the date, time and receipt number of the transfer.

  my ($from);
  my ($account);
  foreach $account ($bank->accounts()) {
	if ($account->type() eq 'MasterCard') {
		$from = $account;
	}
  }
  my ($to) = new Finance::Bank::Commonwealth::Account({
                    'bsb'           => '654321',
                    'number'        => '12345678',
                    'type'          => 'BankAccount',
                    'name'          => 'Bob\'s Account',
				});

  my ($success) = $bank->transfer($from, $to, 1.50, "Why this should be");
  if ($success) {
    print "Date:" . $success->date() . "\n";
    print "Time:" . $success->time() . "\n";
    print "Receipt Number:" . $success->receipt_number() . "\n";
  }

=cut

sub transfer {
	my ($self, $from, $to, $amount, $comment) = @_;
	my ($success) = {};
	$self->{'accounts'} = undef; # Money is being transferred, so undef the accounts variable 
	if ($self->{'transfer'}->{'url'}) {
		my ($html) = $self->_post($self->{'transfer'}->{'url'}, $self->{'transfer'}->{'fields'});
		my ($fields) = {};
		if ($html =~ m#var\s+aMAIN\s+=(.*?)$#is) {
			$html = $1;
			while ($html =~ m#input type="?hidden"?.*?name="(.*?)".*?value="(.*?)"#isg) {
				$fields->{$1} = $2;	
			}
			while ($html =~ m#input type="?text"?.*?name="(.*?)".*?value="(.*?)"#isg) {
				$fields->{$1} = $2;	
			}
			$fields->{'EWF_BUTTON_OK'} = 'OK';
			if ($html =~ m#SELECT NAME="DATA1(.*?)\/SELECT#is) {
				my ($transferFromHTML) = $1;
				my ($fromId) = $from->id();
				my ($matched) = 0;
				FROM_ACCOUNT: while ($transferFromHTML =~ m#OPTION\s*VALUE="(.*?)".*?>(.*?)</OPTION>#isg) {
					my ($optionValue) = $1;
					my ($optionText) = $2;
					if ($optionValue eq $fromId) {
						$fields->{'DATA1'} = $optionValue;
						$matched = 1;
						last FROM_ACCOUNT;
					}
				}
				unless ($matched) { 
					die "The from account does not match the available choices"; 
				}
			} else {
				die "Failed to parse HTML";
			}
			if ($html =~ m#SELECT NAME="DATA2(.*?)\/SELECT#is) {
				my ($transferToHTML) = $1;
				my ($toId) = $to->id();
				my ($matched) = 0;
				TO_ACCOUNT: while ($transferToHTML =~ m#OPTION\s*VALUE="(.*?)">(.*?)</OPTION>#isg) {
					my ($optionValue) = $1;
					my ($optionText) = $2;
					if ($optionValue !~ m#NOTHING#) {
						if ($optionValue =~ m#(\d+)#) {
							my ($accountId) = $1;
							if (($toId eq $accountId) && ($optionText !~ m#N\/A available#)) {
								$self->{'transfer'}->{'fields'}->{'DATA2'} = $optionValue;
								$matched = 1;
								last TO_ACCOUNT;
							}
						}
						if ($optionValue =~ m#open#is) {
							if (($to->bsb()) && ($to->number())) {
								my ($tmpOptionText) = $optionText;
								$tmpOptionText =~ s#\D##g;
								my ($fullAccountId) = $to->bsb() . $to->number();
								if ($tmpOptionText eq $fullAccountId) {
									$fields->{'DATA2'} = $optionValue;
									$matched = 1;
									last TO_ACCOUNT;
								}
							}
						}
					}
				}
				$fields->{'DATA8'} = $comment; 
				if ($matched) {
					$fields->{'DATA4'} = '';
					$fields->{'DATA5'} = '';
					$fields->{'DATA6'} = '';
				} else {
					$fields->{'DATA2'} = 'NOTHING';
					$fields->{'DATA4'} = $to->name();
					$fields->{'DATA5'} = $to->bsb();
					$fields->{'DATA6'} = $to->number();
					unless (($fields->{'DATA4'}) &&
							($fields->{'DATA5'}) &&
							($fields->{'DATA6'}) &&
							($fields->{'DATA8'})) {
						die "Failed to specify all the correct fields for a new transfer";
					}
				}
			}
			$fields->{'DATA3'} = $amount;
			$html = $self->_post($self->{'transfer'}->{'url'}, $fields);
			my ($url);
			if ($html =~ m#FORM\s+METHOD="POST"\s+ACTION="(.*?)"\s+NAME="APPS_FORM_MAIN"#is) {
				$url = $1;
				$fields = {};
				while ($html =~ m#input type="?hidden"?.*?name="(.*?)".*?value="(.*?)"#isg) {
					$fields->{$1} = $2;
				}
				while ($html =~ m#input type="?text"?.*?name="(.*?)".*?value="(.*?)"#isg) {
					$fields->{$1} = $2;
				}
				$fields->{'EWF_BUTTON_OK'} = 'OK';
				$html = $self->_post($url, $fields);
				my ($date, $time, $receiptNumber);
				if ($html =~ m#Date:.*?>(\d{2}\/\d{2}\/\d{4})<#is) {
					$date = $1;
				} else {
					die "Failed to confirm payment date";
				}
				if ($html =~ m#Time:.*?>(\d{2}:\d{2}:\d{2}.*?)<#is) {
					$time = $1;
				} else {
					die "Failed to confirm payment time";
				}
				if ($html =~ m#Receipt Number:.*?>(N\d+)<#is) {
					$receiptNumber = $1;
				} else {
					die "Failed to confirm receipt number";
				}
				return (Finance::Bank::Commonwealth::Success->new({
							'date' => $date,
							'time' => $time,
							'receipt_number' => $receiptNumber
								}));
			}
		}
	}
	return 0;
}

=head2 accounts

The accounts method returns an array of Finance::Bank::Commonwealth::Account objects that are connected to the current login.

  foreach $account ($bank->accounts()) {
      print "Account Id: ". $account->id() . "\n";
      print "Account Code: ". $account->code() . "\n";
      print "Account BSB: " . $account->bsb() . "\n";
      print "Account Number: " . $account->number() . "\n";
      print "Account Name: " . $account->name() . "\n";
      print "Account Type: " . $account->type() . "\n";
      print "Account Balance: " . $account->balance() . "\n";
      print "Available Funds: " . $account->available() ."\n";
  }

=cut

sub accounts {
	my ($self) = @_;
	unless (defined $self->{'accounts'}) {
# 
# Account information can be returned as a 'return value' and is 
# cached until a transfer or bpay type method is called.
#
		if ($self->{'get_accounts'}->{'url'}) {
			my ($html) = $self->_post($self->{'get_accounts'}->{'url'}, $self->{'get_accounts'}->{'fields'});
			if ($html =~ m#var\s+aMAIN\s+=(.*?)$#is) {
				$html = $1;
				$self->_parse_accounts($html);
			}
		}
	}
	return (@{$self->{'accounts'}});
}

sub _parse_accounts {
	my ($self, $html) = @_;
	while ($html =~ m#S_FORM_MAIN, \\\'DETAILS\\\', \\\'(.*?)\\\'\)" on.*?true;">(.*?)<\/A>.*?true;">(.*?)<\/A>.*?">(.*?)<\/TD>.*?">(.*?)<\/TD>#isg) {
		push @{$self->{'accounts'}}, Finance::Bank::Commonwealth::Account->new({ 
				'id' => $1,
				'code' => $2,
				'type' => $3,
				'balance' => $4,
				'available_funds' => $5, 
					});
	}
}

=head2 transactions($account)

The transactions method returns an array of Finance::Bank::Commonwealth::Transaction objects that are connected to the $account specified.  Note that this method will NOT yet return all the available transactions.  It will only return the most recent transactions. This method will also check the banks accounting and make sure that all the balances actually add up.  (We all trust banks :)).

  my ($transaction);
  print "---------------------------------------------\n";
  foreach $transaction ($bank->transactions($from)) {
    print "Transaction Date: " . $transaction->date() . "\n";
    print "Transaction Reason: " . $transaction->reason() . "\n";
    print "Transaction Amount: " . $transaction->amount() . "\n";
    print "Transaction Total: " . $transaction->total() . "\n";
    print "---------------------------------------------\n";
  }

=cut

sub transactions {
	my ($self, $transactionAccount) = @_;
	$self->{'accounts'} = undef;
	my ($transactions) = [];
	if ($self->{'get_accounts'}->{'url'}) {
		my ($html) = $self->_post($self->{'get_accounts'}->{'url'}, $self->{'get_accounts'}->{'fields'});
		if ($html =~ m#var\s+aMAIN\s+=(.*?)$#is) {
			$html = $1;
			$self->_parse_accounts($html);
		}
		my ($account, $matched);
		my ($match);
		LISTED_ACCOUNT: foreach $account ($self->accounts()) {
			if (($account->bsb() eq $transactionAccount->bsb()) &&
				($account->number() eq $transactionAccount->number())) 
			{
				$matched = 1;
				$match = $account;
				last LISTED_ACCOUNT;
			}
		}
		if ($matched) {
			if ($html =~ m#FORM TARGET="main" METHOD="POST" ACTION="(.*?)" NAME="APPS_FORM_MAIN"#is) {
				my ($url) = $1;
				my ($fields) = {};
				while ($html =~ m#input type="?hidden"?.*?name="(.*?)".*?value="(.*?)"#isg) {
					$fields->{$1} = $2;
				}
				my ($requiredFields) = {		'DATA1' => '',
									'EWFBUTTON' => '',
									'EWF_SYS_0' => undef,
									'SEQUENCE_NUMBER' => 2,
									'EWF_SYS_1' => undef,
									'EWF_FORM_NAME' => 'LEV2 Main',
									'TEMPLATE_FILE' => 'Zbalrevw.htm',
									'DISPLAYPAGE' => 'ZBAL-ACCOUNT BALANCE PAGE',
							};
				$self->_checkFields($fields, $requiredFields);
				$fields->{'DATA1'} = $match->id();
				$fields->{'EWFBUTTON'} = 'Submit';
				$fields->{'EWF_BUTTON_DETAILS'} = 'DETAILS';
				$html = $self->_post($url, $fields);
				my ($date, $reason, $creditOrDebitText, $amount, $total);
				$html =~ s#<BR># #isg; # sometimes <BR>s can occur in the reason field which stuffs up the following pattern match
				my (@checkTotals) = ();
				while ($html =~ m#>(\d\d/\d\d/\d\d\d\d)<.*?>(\w.*?)<(.*?\$.*?)>(\$.*?)<#isg) {
					$date = $1;
					$reason = $2;
					$creditOrDebitText = $3;
					$total = $4;
					if ($creditOrDebitText =~ m#.*?"2"></FONT.*?"2">(\$.*?)<#is) {
						$amount = $1 . " CR"; # Credit
					} elsif ($creditOrDebitText =~ m#.*?"2">(\$.*?)<.*?"2"></FONT#is) {
						$amount = $1 . " DR"; # Debit
					}
					push @$transactions, Finance::Bank::Commonwealth::Transaction->new({ 
								'date' => $date,
								'reason' => $reason,
								'amount' => $amount,
								'total' => $total
									});
					unshift @checkTotals, Finance::Bank::Commonwealth::Transaction->new({ 
								'date' => $date,
								'reason' => $reason,
								'amount' => $amount,
								'total' => $total
									});
				}
				if ((scalar @checkTotals) > 1) {
					my ($checkTotal) = $checkTotals[0]->total();
					my ($banksTotal) = $checkTotals[-1]->total();
					shift @checkTotals; # don't count the first amount
					my ($transaction);
					my ($warn);
					foreach $transaction (@checkTotals) {
						$warn = "Summing...$checkTotal + " . $transaction->amount() . " =";
						$checkTotal += $transaction->amount();
						warn "$warn $checkTotal\n" if ($Finance::Bank::Commonwealth::debug);
					}
					unless (($checkTotal == $banksTotal) || ($checkTotal eq $banksTotal)) {
						warn "Bank's accounting is questionable!! Their total $banksTotal should be $checkTotal!!!\n";
					}
				}
			} else {
				die "Failed to parse main screen for Transaction Details";
			}	
		} else {
			die "Failed to get this accounts details";
		}
	}
	return (@$transactions);
}

=head2 bpay($from, $biller, $amount)

The bpay method allows a payment of $amount to be made from the $from account to the $biller.  The method will return a Finance::Bank::Commonwealth::Success object that gives the date, time and receipt number of the transfer.

  $from = new Finance::Bank::Commonwealth::Account({
                           'bsb' => '063011',
                           'number' => '10127167',
                           'type' => 'Streamline'
                                  });

  my ($biller) = new Finance::Bank::Commonwealth::Biller({ 
                                  'code' => '8789',
                                  'ref_no' => '221019047125' });

  my ($success) = $bank->bpay($from, $biller, .50);
  if ($success) {
    print "Date:" . $success->date() . "\n";
    print "Time:" . $success->time() . "\n";
    print "Receipt Number:" . $success->receipt_number() . "\n";
  }

=cut

sub bpay {
	my ($self, $from, $biller, $amount) = @_;
	$self->{'accounts'} = undef; # Money is being paid, so undef the accounts variable 
	if ($self->{'get_billing_info'}->{'url'}) {
		my ($html) = $self->_post($self->{'get_billing_info'}->{'url'}, $self->{'get_billing_info'}->{'fields'});
		my ($fields, $url);
		if ($html =~ m#var\s+aMAIN\s+=(.*?)$#is) {
			$html = $1;
			if ($html =~ m#<form TARGET="main" METHOD="POST" ACTION="(.*?)" NAME="APPS_FORM_MAIN">#is) {
				$url = $1;
				while ($html =~ m#input.*?name="?(.*?)"? .*?value="(.*?)"#isg) {
					$fields->{$1} = $2;
				}
				my ($requiredFields) = {	'DISPLAYPAGE' => 'ZBPY-MAIN PAY BILL PAGE',
								'EWF_BUTTON_OK' => '',
								'EWF_BUTTON_SCHEDULE' => '',
								'EWF_FORM_NAME' => 'LEV2 Main',
								'EWF_SYS_0' => undef,
								'EWF_SYS_1' => undef,
								'PayBill' => '  Pay Bill Now ',
								'SEQUENCE_NUMBER' => 2,
								'STORE' => '',
								'SchedBill' => ' Schedule Bill Pay ',
								'TEMPLATE_FILE' => 'Zbpymain.htm',
							};
				$self->_checkFields($fields, $requiredFields);
				$html =~ m#<SELECT NAME="DATA1"(.*?)SELECT>#is;
				my ($accountsHTML) = $1;
				my ($matched, $accountId);
				$fields->{'DATA1'} = 'Select an account';
				ACCOUNT: while ($accountsHTML =~ m#OPTION.*?VALUE="(.*?)".*?>(.*?)<#isg) {
					$accountId = $1;
					if ($accountId eq $from->id()) {
						$matched = 1;
						$fields->{'DATA1'} = $from->id();
						last ACCOUNT;
					}
				}
				unless ($matched) {
					die "Failed to find account in list.";
				}
				my ($id, $code, $name, $refNo);
				$matched = 0;
				BILLER: while ($html =~ m#DATA2" VALUE="(.*?)".*?SIZE="2">0+(.*?)<BR>(.*?)</F.*?CRN.*?VALUE="(.*?)"#isg) {
					$id = $1;
					$code = $2;
					$name = $3;
					$refNo = $4;
					if ($code eq $biller->code()) {
						$matched = 1;
						$fields->{'DATA2'} = $id;
						$fields->{"CRN$id"} = $biller->customer_ref_no();
						$fields->{"Amount$id"} = $amount;
						$fields->{'DATA3'} = $fields->{"CRN$id"};
						$fields->{'DATA4'} = $fields->{"Amount${id}"};
						$fields->{'EWF_BUTTON_OK'} = 'OK';
						last BILLER;
					}
				}
				unless ($matched) {
					die "Failed to find biller " . $biller->code() . ". Please add manually";
				}
				$html = $self->_post($url, $fields);
				if ($html =~ m#<form.*?METHOD="POST".*?ACTION="(.*?)".*?NAME="APPS_FORM_MAIN"#is) {
					$url = $1;
					$fields = {};
					while ($html =~ m#input.*?type="?hidden"?.*?name="?(.*?)"? .*?value="(.*?)"#isg) {
						$fields->{$1} = $2;
					}
					$requiredFields = {		'EWFBUTTON' => '',
									'DATA1'	=> $from->id(),
									'SEQUENCE_NUMBER' => 3,
									'DATA2' => $id,
									'TEMPLATE_FILE' => 'Zbpyconf.htm',
									'DISPLAYPAGE' => 'ZBPY-BILL CONFIRMATION PAGE',
									'EWF_SYS_0' => undef,
									'EWF_SYS_1' => undef,
									'EWF_FORM_NAME' => 'LEV2 Main',
							};
					$self->_checkFields($fields, $requiredFields);	
					$fields->{'EWF_BUTTON_OK'} = 'OK';
					$fields->{'EWFBUTTON'} = 'OK';
					$html = $self->_post($url, $fields);
					my ($date, $time, $receiptNumber);
					if ($html =~ m#Date:.*?>(\d{2}\/\d{2}\/\d{4})<#is) {
						$date = $1;
					} else {
						die "Failed to confirm payment date";
					}
					if ($html =~ m#Time:.*?>(\d{2}:\d{2}:\d{2}.*?)<#is) {
						$time = $1;
					} else {
						die "Failed to confirm payment time";
					}
					if ($html =~ m#Receipt Number:.*?>(N\d+)<#is) {
						$receiptNumber = $1;
					} else {
						die "Failed to confirm receipt number";
					}
					return (Finance::Bank::Commonwealth::Success->new({
								'date' => $date,
								'time' => $time,
								'receipt_number' => $receiptNumber
									}));
				}
			} else {
				die "Failed to find url for https request";
			}
		} else {
			die "Failed to parse billers page";
		}
	}
}

sub _get {
	my ($self, $url) = @_;

	$url =~ m#^(.*?)://(.*?)\/(.*?)$#i;
	my ($method, $host, $action) = ($1, $2, $3);
	if ($method eq 'http') {
		my ($ua) = LWP::UserAgent->new();
		$ua->agent($self->{'user_agent'});

		my $req = HTTP::Request->new(GET => $url);
		my $res = $ua->request($req);
		if ($res->is_success()) {
			return ($res->content());
		} else {
			die "Failed $res->status_line";
		}
	} elsif ($method eq 'https') {
		$action = '/' . $action;
		my ($page) = Net::SSLeay::get_https($host, 443, $action);
		return ($page);
	} else {
		die "Unknown method $method from $url...\n";
	}
}

sub _post {
	my ($self, $url, $parameters) = @_;

	$url =~ m#^(.*?)://(.*?)\/(.*?)$#i;
	my ($method, $host, $action) = ($1, $2, $3);
	if ($method eq 'https') {
		$action = '/' . $action;
		my ($page) = Net::SSLeay::post_https($host, 443, $action, Net::SSLeay::make_headers( 'User-Agent' => $self->{'user_agent'} ), Net::SSLeay::make_form(%$parameters));
		return ($page);
	} else {
		die "Unknown method $method from $url...\n";
	}
}

sub _checkFields {
	my ($self, $fields, $requiredFields) = @_;
	my ($key);
	foreach $key (keys %$requiredFields) {
		unless (defined $fields->{$key}) {
			die "Failed to find required field $key.  This means that the source HTML may have changed.  Complete audit of source HTML is required.";
		}
		if (defined $requiredFields->{$key}) {
			unless ($requiredFields->{$key} eq $fields->{$key}) {
				die "Failed to verify correct value of required field $key.  This means that the source HTML may have changed.  Complete audit of source HTML is required.";
			}
		}
	}
}

=head1 AUTHOR

David Dick (ddick@cpan.org)

=head1 VERSION

v0.99 released 15 Aug 2002

=head1 COPYRIGHT

Copyright (c) 2002 David Dick.  All rights reserved.  This program is free software; you may redistribute it and/or modify it under the same terms as Perl itself

=cut

package Finance::Bank::Commonwealth::Account;
use strict;
 
sub new {
        my ($proto, $params) = @_;
        my ($class) = ref($proto) || $proto;
        my ($self) = {};
	my ($key);
	if ($params->{'bsb'} && ($params->{'number'})) {
		$params->{'bsb'} =~ m#^\d{2}(\d{4})$# || die "BSB must have six digits";
		my ($bsbSuffix) = $1;
		$params->{'number'} =~ m#^(\d{4})(\d{4})$# || die "Account Number must have eight digits";
		my ($accNumPrefix, $accNumSuffix) = ($1, $2);
		$params->{'id'} = $bsbSuffix . $params->{'number'};
		$params->{'code'} = $bsbSuffix . " " . $accNumPrefix . " " . $accNumSuffix;
		$self->{'account_bsb'} = $params->{'bsb'};
		$self->{'account_number'} = $params->{'number'};
	} elsif (($params->{'type'} eq 'Streamline') || 
				($params->{'type'} eq 'AwardSaver'))
	{
		$params->{'id'} =~ m#^(\d{4})(\d{8})$# || die "Account Id must have twelve digits for these account types";
		$self->{'account_bsb'} = '06' . $1;
		$self->{'account_number'} = $2;
	} else {
		$self->{'bsb'} = '';
		$self->{'number'} = '';
	}
	unless ($params->{'type'}) {
		die "New $class must have an type";
	}
	unless (($params->{'type'} eq 'Streamline') || 
			($params->{'type'} eq 'BankAccount') ||
			($params->{'type'} eq 'AwardSaver') ||
			($params->{'type'} eq 'Other') ||
			($params->{'type'} eq 'MasterCard') ||
			($params->{'type'} eq 'Visa')) 
	{
		die "Failed to recognise an account_type of " . $params->{'type'};
	}
	$self->{'account_id'} = $params->{'id'} || die "New $class must have an id";
	$self->{'account_code'} = $params->{'code'} || die "New $class must have a code";
	$self->{'account_type'} = $params->{'type'} || die "New $class must have a type";
	$self->{'account_name'} = $params->{'name'} || '';
	if ($params->{'balance'}) {
		my ($float) = $params->{'balance'};
		if ($float =~ m#DR#is) {
			$float =~ s#[^\d.]##ig;
			$float = $float * -1;
		} else {
			$float =~ s#[^\d.]##ig;
		}
		$self->{'account_balance'} = $float;
	} else {
		$self->{'account_balance'} = '0';
	}
	if ($params->{'available_funds'}) {
		my ($float) = $params->{'available_funds'};
		if ($float =~ m#DR#is) {
			$float =~ s#[^\d.]##ig;
			$float = $float * -1;
		} else {
			$float =~ s#[^\d.]##ig;
		}
		$self->{'available_funds'} = $float;
	} else {
		$self->{'available_funds'} = '0';
	}
	bless $self, $class;
	return ($self);
}

sub id {
	my ($self) = @_;
	return ($self->{'account_id'});
}

sub code {
	my ($self) = @_;
	return ($self->{'account_code'});
}

sub name {
	my ($self) = @_;
	return ($self->{'account_name'});
}

sub type {
	my ($self) = @_;
	return ($self->{'account_type'});
}

sub bsb {
	my ($self) = @_;
	return ($self->{'account_bsb'});
}

sub number {
	my ($self) = @_;
	return ($self->{'account_number'});
}

sub balance {
	my ($self) = @_;
	return ($self->{'account_balance'});
}

sub available {
	my ($self) = @_;
	return ($self->{'available_funds'});
}

package Finance::Bank::Commonwealth::Biller;
use strict;
 
sub new {
        my ($proto, $params) = @_;
        my ($class) = ref($proto) || $proto;
        my ($self) = {};
	my ($key);
	$self->{'biller_id'} = $params->{'id'};
	$self->{'biller_code'} = $params->{'code'} || die "New $class must have a Biller Code";
	$self->{'biller_name'} = $params->{'name'};
	$self->{'customer_ref_no'} = $params->{'ref_no'} || die "New $class must have a Customer Reference Number";
	bless $self, $class;
	return ($self);
}

sub id {
	my ($self) = @_;
	return ($self->{'biller_id'});
}

sub code {
	my ($self) = @_;
	return ($self->{'biller_code'});
}

sub name {
	my ($self) = @_;
	return ($self->{'biller_name'});
}

sub customer_ref_no {
	my ($self) = @_;
	return ($self->{'customer_ref_no'});
}

package Finance::Bank::Commonwealth::Success;
use strict;
 
sub new {
        my ($proto, $params) = @_;
        my ($class) = ref($proto) || $proto;
        my ($self) = {};
	my ($key);
	$self->{'date'} = $params->{'date'};
	$self->{'time'} = $params->{'time'};
	$self->{'receipt_number'} = $params->{'receipt_number'};
	bless $self, $class;
	return ($self);
}

sub date {
	my ($self) = @_;
	return ($self->{'date'});
}

sub time {
	my ($self) = @_;
	return ($self->{'time'});
}

sub receipt_number {
	my ($self) = @_;
	return ($self->{'receipt_number'});
}

package Finance::Bank::Commonwealth::Transaction;
use strict;
 
sub new {
        my ($proto, $params) = @_;
        my ($class) = ref($proto) || $proto;
        my ($self) = {};
	my ($key);
	$self->{'transaction_date'} = $params->{'date'} || die "New $class must have a date";
	$self->{'transaction_reason'} = $params->{'reason'} || '';
	if ($params->{'amount'}) {
		my ($float) = $params->{'amount'};
		if ($float =~ m#DR#is) {
			$float =~ s#[^\d.]##ig;
			$float = $float * -1;
		} else {
			$float =~ s#[^\d.]##ig;
		}
		$self->{'transaction_amount'} = $float;
	} else {
		$self->{'transaction_amount'} = '0';
	}
	if ($params->{'total'}) {
		my ($float) = $params->{'total'};
		if ($float =~ m#DR#is) {
			$float =~ s#[^\d.]##ig;
			$float = $float * -1;
		} else {
			$float =~ s#[^\d.]##ig;
		}
		$self->{'transaction_total'} = $float;
	} else {
		$self->{'transaction_total'} = '0';
	}
	bless $self, $class;
	return ($self);
}

sub date {
	my ($self) = @_;
	return ($self->{'transaction_date'});
}

sub reason {
	my ($self) = @_;
	return ($self->{'transaction_reason'});
}

sub amount {
	my ($self) = @_;
	return ($self->{'transaction_amount'});
}

sub total {
	my ($self) = @_;
	return ($self->{'transaction_total'});
}

1;
