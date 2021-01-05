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

Bio::EnsEMBL::Compara::PipeConfig::EG::GeneMemberHomologyStats_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::EG::GeneMemberHomologyStats_conf -host mysql-ens-compara-prod-X -port XXXX \
      -curr_rel_db <curr_rel_compara_eg_db_url> -collection <collection_name>

=head1 DESCRIPTION

    A simple pipeline to populate the gene_member_hom_stats table
    for a single collection.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::EG::GeneMemberHomologyStats_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::PipeConfig::GeneMemberHomologyStatsFM_conf');

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        'compara_db'    => $self->o('curr_rel_db'),     # For backwards compatibility
    }
}

1;
