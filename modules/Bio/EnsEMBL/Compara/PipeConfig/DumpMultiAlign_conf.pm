=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 SYNOPSIS

Initialise the pipeline on comparaY, grouping the alignment blocks
according to their "homo_sapiens" chromosome

  init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::DumpMultiAlign_conf --mlss_id 548 --compara_db mysql://ensro@comparaX/msa_db_to_dump --output_dir /path/to/dumps/ --species homo_sapiens --host comparaY

Release 65

epo 6 way: 3.4 hours
epo 12 way: 2.7 hours
mercator/pecan 19 way: 5.5 hours
low coverage epo 35 way: 43 hours (1.8 days)

=cut

package Bio::EnsEMBL::Compara::PipeConfig::DumpMultiAlign_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::EnsemblGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


sub default_options {
    my ($self) = @_;
    return {
	%{$self->SUPER::default_options},   # inherit the generic ones

        'staging_loc1' => {                     # general location of half of the current release core databases
            -host   => 'ens-staging1',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
	    -driver => 'mysql',
	    -dbname => $self->o('ensembl_release'),
        },

        'staging_loc2' => {                     # general location of the other half of the current release core databases
            -host   => 'ens-staging2',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
	    -driver => 'mysql',
	    -dbname => $self->o('ensembl_release'),
        },

        'livemirror_loc' => {                   # general location of the previous release core databases (for checking their reusability)
            -host   => 'ens-livemirror',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
            -driver => 'mysql',
        },

        # By default, the pipeline will follow the "locator" of each
        # genome_db. You only have to set db_urls or reg_conf if the
        # locators are missing.

	#Location of core and, optionally, compara db
	#'db_urls' => [ $self->dbconn_2_url('staging_loc1'), $self->dbconn_2_url('staging_loc2') ],
	'db_urls' => [],

	#Alternative method of defining location of dbs
	'reg_conf' => '',

	#Compara reference to dump. Can be the "species" name (if loading via db_urls) or the url
        # Intentionally left empty
	#'compara_db' => 'Multi',

	'species'  => "human",
	'split_size' => 200,
	'masked_seq' => 1,
        'format' => 'emf',
        'dump_program' => $self->o('ensembl_cvs_root_dir')."/ensembl-compara/scripts/dumps/DumpMultiAlign.pl",
	'species_tree_file' => $self->o('ensembl_cvs_root_dir')."/ensembl-compara/scripts/pipeline/species_tree.ensembl.topology.nw",

    };
}

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

	#Store DumpMultiAlign other_gab genomic_align_block_ids
        $self->db_cmd('CREATE TABLE other_gab (genomic_align_block_id bigint NOT NULL)'),

	#Store DumpMultiAlign healthcheck results
        $self->db_cmd('CREATE TABLE healthcheck (filename VARCHAR(400) NOT NULL, expected INT NOT NULL, dumped INT NOT NULL)'),
	
	'mkdir -p '.$self->o('output_dir'), #Make dump_dir directory
    ];
}


# Ensures species output parameter gets propagated implicitly
sub hive_meta_table {
    my ($self) = @_;

    return {
        %{$self->SUPER::hive_meta_table},
        'hive_use_param_stack'  => 1,
    };
}


sub resource_classes {
    my ($self) = @_;

    return {
            %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class
            '2GbMem' => { 'LSF' => '-C0 -M2000 -R"select[mem>2000] rusage[mem=2000]"' },
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
	 {  -logic_name => 'initJobs',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::InitJobs',
            -parameters => {'species' => $self->o('species'),
			    'mlss_id' => $self->o('mlss_id'),
			    'compara_db' => $self->o('compara_db'),
			   },
            -input_ids => [
                {
                    'format'    => $self->o('format'),
                }
            ],
            -flow_into => {
                '2->A' => [ 'createChrJobs' ],
                '3->A' => [ 'createSuperJobs' ],
                '4->A' => [ 'createOtherJobs' ],
		'A->1' => [ 'md5sum'],
            },
        },
	 {  -logic_name    => 'createChrJobs',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateChrJobs',
            -parameters    => {
			       'compara_db' => $self->o('compara_db'),
			       'split_size' => $self->o('split_size'),
			      },
	    -flow_into => {
	       2 => [ 'dumpMultiAlign' ] #must be on branch2 incase there are no results
            }	    
        },
	{  -logic_name    => 'createSuperJobs',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateSuperJobs',
            -parameters    => {
			       'compara_db' => $self->o('compara_db'),
			      },
	    -flow_into => {
	       2 => [ 'dumpMultiAlign' ]
            }
        },
	{  -logic_name    => 'createOtherJobs',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::CreateOtherJobs',
            -parameters    => {'species' => $self->o('species'),
			       'compara_db' => $self->o('compara_db'),
			       'split_size' => $self->o('split_size'),
			      },
	   -rc_name => '2GbMem',
	    -flow_into => {
	       2 => [ 'dumpMultiAlign' ]
            }
        },
	{  -logic_name    => 'dumpMultiAlign',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::DumpMultiAlign',

            -parameters    => {
                               'cmd' => [ 'perl', $self->o('dump_program'), '--species', $self->o('species'), '--mlss_id', $self->o('mlss_id'), '--masked_seq', $self->o('masked_seq'), '--split_size', $self->o('split_size'), '--output_format', '#format#' ],
			       "reg_conf" => $self->o('reg_conf'),
			       "db_urls" => $self->o('db_urls'),
			       "compara_db" => $self->o('compara_db'),
			       "num_blocks"=> "#num_blocks#",
			       "output_dir"=> $self->o('output_dir'),
			       "output_file"=>"#output_file#" , 
			      },
	   -hive_capacity => 15,
	   -rc_name => '2GbMem',
           -flow_into => [ 'compress' ],
        },
        {   -logic_name     => 'compress',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters     => {
                'cmd'           => 'gzip -f -9 #output_dir#/#output_file#',
                'output_dir'    => $self->o('output_dir'),
            },
            -hive_capacity => 200,
        },
	{  -logic_name    => 'md5sum',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::MD5SUM',
            -parameters    => {'output_dir' => $self->o('output_dir'),},
            -flow_into    => [ 'readme' ],
        },
	{  -logic_name    => 'readme',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMultiAlign::Readme',
            -parameters    => {
			       'compara_db' => $self->o('compara_db'),
			       'mlss_id' => $self->o('mlss_id'),
			       'output_dir' => $self->o('output_dir'),
			       'split_size' => $self->o('split_size'),
			       'species_tree_file' => $self->o('species_tree_file'),
			       'species' => $self->o('species'),
			      },
        },    

    ];
}

1;
