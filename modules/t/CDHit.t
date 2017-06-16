#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2017] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Data::Dumper;
use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

BEGIN {
    use Test::Most;
    use File::Compare;
    use File::Temp qw(tempdir);
    use File::Copy qw(copy);
}

# check module can be seen and compiled
use_ok('Bio::EnsEMBL::Compara::RunnableDB::CDHit'); 

# my $tmp = tempdir( CLEANUP => 1 );
# copy 'cdhit_data/test.fastadb', "$tmp/test.blastdb";

my ( $branch1_dataflow, $branch2_dataflow );

$branch1_dataflow = [
	{ genome_db_id => 134 },
	{ genome_db_id => 150 },
	{ genome_db_id => 125 },
];
$branch2_dataflow = [ 
	{ source_seq_member_id => 621010, 
	  target_seq_member_id => 622175, 
	  identity => '100.00'
	},
	{ source_seq_member_id => 621010, 
	  target_seq_member_id => 622235, 
	  identity => '100.00' 
	},
	{ source_seq_member_id => 943204 },
	{ source_seq_member_id => 768254, 
	  target_seq_member_id => 768261, 
	  identity => '100.00'
	},
	{ source_seq_member_id => 768254, 
	  target_seq_member_id => 768430, 
	  identity => '100.00' 
	},
	{ source_seq_member_id => 768254, 
	  target_seq_member_id => 768550, 
	  identity => '100.00' 
	},
	{ source_seq_member_id => 768254, 
	  target_seq_member_id => 768620, 
	  identity => '100.00' 
	},
	{ source_seq_member_id => 634759 },
	{ source_seq_member_id => 770780 },
	{ source_seq_member_id => 1496856 },
];

standaloneJob(
	'Bio::EnsEMBL::Compara::RunnableDB::CDHit', # module
	{ # input param hash
		'cdhit_exe'                => 'fake_cdhit',
		'cdhit_identity_threshold' => 100,
		#'fasta_name'               => 'cdhit_data/test.fastadb',
		'fasta_dir'                => 'cdhit_data',
		'genome_db_ids'            => [134, 150, 125],
		'cluster_file'             => 'cdhit_data/test.clstr',
		'cdhit_outfile'            => 'cdhit_data/test.out',
	},
	[ # list of events to test for (just 1 event in this case)
		[ # start event
			'DATAFLOW', # event to test for (could be WARNING)
			$branch1_dataflow,
			2 # dataflow branch
		], # end event
		[
            'DATAFLOW',
            $branch2_dataflow,
            3
        ]
	]
);

# test that blast database file is as expected
# ok( compare("$tmp/test.blastdb", 'cdhit_data/test.exp.blastdb') == 0, 'blast database contents ok' );

done_testing();