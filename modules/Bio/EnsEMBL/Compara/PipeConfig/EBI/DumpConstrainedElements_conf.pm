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

=head1 SYNOPSIS

Pipeline to dump conservation scores as bedGraph and bigWig files

    $ init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::EBI::DumpConstrainedElements_conf -compara_url $(mysql-ens-compara-prod-4 details url mateus_epo_low_68_way_mammals_92) -mlss_id 1136 $(mysql-ens-compara-prod-2-ensadmin details hive)

=cut

package Bio::EnsEMBL::Compara::PipeConfig::EBI::DumpConstrainedElements_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::PipeConfig::DumpConstrainedElements_conf');


sub default_options {
    my ($self) = @_;
    return {
        %{$self->SUPER::default_options},   # inherit the generic ones

        # How many species can be dumped in parallel
        'dump_ce_capacity'    => 50,
    };
}


1;
