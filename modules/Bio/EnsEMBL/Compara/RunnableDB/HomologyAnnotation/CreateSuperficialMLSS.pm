=head1 LICENSE

See the NOTICE file distributed with this work for additional information
regarding copyright ownership.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::HomologyAnnotation::CreateSuperficialMLSS

=head1 DESCRIPTION

Create superficial MLSS for each C<genome_db_id> and C<target_genome_db_id> pair.
Optionally dataflow seq_member_ids in batches using C<step>.

=cut

package Bio::EnsEMBL::Compara::RunnableDB::HomologyAnnotation::CreateSuperficialMLSS;

use warnings;
use strict;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;
use Data::Dumper;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

sub param_defaults {
    my ($self) = @_;
    return {
        %{$self->SUPER::param_defaults},
        'step'        => 1000,
    }
}

sub run {
    my $self = shift;

    my $query_gdb_id   = $self->param_required('genome_db_id');
    my $hit_gdb_id     = $self->param_required('target_genome_db_id');
    my $ref_db         = Bio::EnsEMBL::Compara::DBSQL::DBAdaptor->go_figure_compara_dba($self->param_required('rr_ref_db'));
    my $seq_members    = $self->compara_dba->get_SeqMemberAdaptor->fetch_all_canonical_by_GenomeDB($query_gdb_id);
    my @seq_member_ids = map {$_->dbID} @$seq_members;
    my @sorted_seq_ids = sort { $a <=> $b } @seq_member_ids;

    # MLSS will not exist for hit_gdb: it is a reference and belongs to a different db
    my $mlss = $self->_create_and_store_superficial_mlss($self->compara_dba->get_GenomeDBAdaptor->fetch_by_dbID($query_gdb_id), $ref_db->get_GenomeDBAdaptor->fetch_by_dbID($hit_gdb_id));

    $self->param('full_member_id_list', \@sorted_seq_ids);

}

sub write_output {
    my $self = shift;

    my $query_gdb_id   = $self->param_required('genome_db_id');
    my $hit_gdb_id     = $self->param_required('target_genome_db_id');
    my $seq_member_ids = $self->param('full_member_id_list');

    if ($self->param('step')) {
        while ( my @member_id_list = splice @$seq_member_ids, 0, $self->param('step') ) {
            # A job is output for every $step query members against each reference diamond db
            my $output_id = { 'member_id_list' => \@member_id_list, 'genome_db_id' => $query_gdb_id, 'target_genome_db_id' => $hit_gdb_id};
            $self->dataflow_output_id($output_id, 2);
        }
    }
    else {
        my $output_id = { 'member_id_list' => $seq_member_ids, 'genome_db_id' => $query_gdb_id, 'target_genome_db_id' => $hit_gdb_id};
        $self->dataflow_output_id($output_id, 2);
    }
}

sub _create_and_store_superficial_mlss {
    my ($self, $gdb1, $gdb2) = @_;

    my $mlss_adap    = $self->compara_dba->get_MethodLinkSpeciesSetAdaptor;
    my $method_adap  = $self->compara_dba->get_MethodAdaptor;
    my $species_adap = $self->compara_dba->get_SpeciesSetAdaptor;
    my $method       = $method_adap->fetch_by_type('ENSEMBL_HOMOLOGUES');
    my $species_set  = $species_adap->fetch_by_GenomeDBs([$gdb1, $gdb2]);

    unless ($species_set) {
        $species_set = Bio::EnsEMBL::Compara::SpeciesSet->new(
            -genome_dbs => [$gdb1, $gdb2],
            -name       => $gdb1->name . "-" . $gdb2->name,
        );
        $species_adap->store($species_set);
    }

    unless ($method) {
        $method = Bio::EnsEMBL::Compara::Method->new(
            -dbID            => 204,
            -type            => 'ENSEMBL_HOMOLOGUES',
            -class           => 'Homology.homology',
            -display_name    => 'Homologues',
            -adaptor         => $method_adap,
        );
        $method_adap->store($method);
    }

    my $method_link_species_set = Bio::EnsEMBL::Compara::MethodLinkSpeciesSet->new(
        -adaptor             => $mlss_adap,
        -method              => $method,
        -species_set         => $species_set,
    );
    $mlss_adap->store($method_link_species_set);
    return $method_link_species_set;
}

1;
