# $Id: Makefile.PL,v 1.00 2002/08/15 11:11:11 ddick Exp $ 

use ExtUtils::MakeMaker;

WriteMakefile(
		'NAME'		=> 'Finance::Bank::Commonwealth',
		'VERSION_FROM'	=> 'lib/Finance/Bank/Commonwealth.pm',
		'PREREQ_PM'	=> {
				'Net::SSLeay' => 1.12,
				'LWP' => '5.5397',
					},
);	
