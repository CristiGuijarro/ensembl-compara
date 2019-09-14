=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

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


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::Parts::MultipleAlignerStats

=head1 DESCRIPTION

Set of analyses to compute statistics on a multiple-alignment database.
It is supposed to be embedded in pipelines.

=head1 AUTHORSHIP

Ensembl Team. Individual contributions can be found in the GIT log.

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with an underscore (_)

=cut

package Bio::EnsEMBL::Compara::PipeConfig::Parts::MultipleAlignerStats;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;   # For WHEN
 
sub pipeline_analyses_multiple_aligner_stats {
    my ($self) = @_;
    return [
        {   -logic_name => 'multiplealigner_stats_factory',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory',
            -rc_name    => '500Mb_job',
            -flow_into  => {
                '2->A' => [ 'multiplealigner_stats' ],
                'A->1' => [ 'block_size_distribution' ],
                    1  => ['gab_stats_semaphore_holder'],
            },
        },

        {   -logic_name => 'multiplealigner_stats',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::MultipleAlignerStats',
            -parameters => {
                'dump_features'     => $self->o('dump_features_exe'),
                'compare_beds'      => $self->o('compare_beds_exe'),
                'bed_dir'           => $self->o('bed_dir'),
                'ensembl_release'   => $self->o('ensembl_release'),
                'output_dir'        => $self->o('output_dir'),
            },
            -rc_name => '4Gb_job',
            -hive_capacity  => 100,
        },

        {   -logic_name => 'block_size_distribution',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::MultipleAlignerBlockSize',
            -flow_into  => [ 'email_stats_report' ],
        },

        {   -logic_name => 'email_stats_report',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::EmailStatsReport',
            -parameters => {
                'stats_exe' => $self->o('epo_stats_report_exe'),
                'email'     => $self->o('email'),
            },
        },

        {   -logic_name => 'gab_stats_semaphore_holder',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into  => {
                '1->A' => ['Genomic_Align_Block_Job_Generator'],
                'A->1' => ['block_stats_aggregator']
                },
        },

        {   -logic_name => 'Genomic_Align_Block_Job_Generator',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                            'mlss_id'  => $self->o('mlss_id'),
                            'contiguous'  => 0,
                            'step'        => 10,
                            'inputquery'  => 'SELECT DISTINCT genomic_align_block_id FROM genomic_align WHERE method_link_species_set_id = #mlss_id# AND dnafrag_id < 10000000000',
                        },
            -rc_name    => '4Gb_job',
            -flow_into  => {
                2 => ['per_block_stats'],
                },
        },

        {   -logic_name =>  'per_block_stats',
            -module     =>  'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::CalculateBlockStats',
            -rc_name    => '2Gb_job',
            -flow_into  => {
                2 => [ '?accu_name=aligned_positions_counter&accu_address={genome_db_id}[]&accu_input_variable=num_of_aligned_positions' ],
                3 => [ '?accu_name=aligned_sequences_counter&accu_address={genome_db_id}[]&accu_input_variable=sum_aligned_seq'],
                4 => [ '?accu_name=aligned_bases_counter&accu_address={from_genome_db_id}{to_genome_db_id}[]&accu_input_variable=num_of_aligned_positions' ]
            },
        },

        {   -logic_name => 'block_stats_aggregator',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomicAlignBlock::BlockStatsAggregator',
            -rc_name    => '8Gb_job',
        },

    ];
}

1;
