# Copyright © (2011) Institut national de l'information
#                    géographique et forestière 
# 
# Géoportail SAV <geop_services@geoportail.fr>
# 
# This software is a computer program whose purpose is to publish geographic
# data using OGC WMS and WMTS protocol.
# 
# This software is governed by the CeCILL-C license under French law and
# abiding by the rules of distribution of free software.  You can  use, 
# modify and/ or redistribute the software under the terms of the CeCILL-C
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info". 
# 
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability. 
# 
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or 
# data to be ensured and,  more generally, to use and operate it in the 
# same conditions as regards security. 
# 
# The fact that you are presently reading this means that you have had
# 
# knowledge of the CeCILL-C license and that you accept its terms.

################################################################################

=begin nd
File: Forest.pm

Class: COMMON::Forest

Creates and manages all graphs, <NNGraph> and <QTree>.

(see forest.png)

We have several kinds of graphs and their using have to be transparent for the forest. That's why we must define functions for all graph's types (as an interface) :
    - computeYourself() : <NNGraph::computeYourself>, <QTree::computeYourself>
    - containsNode(level, i, j) : <NNGraph::containsNode>, <QTree::containsNode>
    - exportForDebug() : <NNGraph::exportForDebug>, <QTree::exportForDebug>

Using:
    (start code)
    use COMMON::Forest

    my $Forest = COMMON::Forest->new(
        $objPyramid, # a COMMON::FilePyramid object
        $objDSL, # a COMMON::DataSourceLoader object
        $param_process, # a hash with following keys : job_number, path_temp, path_temp_common and path_shell
        $storageType, # final storage : FS, CEPH, S3 or SWIFT
    );
    (end code)

Attributes:
    pyramid - <COMMON::FilePyramid> - Images' pyramid to generate, thanks to one or several graphs.
    commands - <Commands> - To compose generation commands (mergeNtiff, work2cache...).
    graphs - <QTree> or <NNGraph> array - Graphs composing the forest, one per data source.
    scripts - <Script> array - Scripts, whose execution generate the images' pyramid.
    splitNumber - integer - Number of script used for work parallelization.
    storageType - string - Pyramid final storage type : FS, CEPH, S3 or SWIFT

=cut

################################################################################

package COMMON::Forest;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;
use List::Util qw(min max);

# My module
use COMMON::QTree;
use COMMON::NNGraph;
use COMMON::Array;

use COMMON::ShellCommands;
use COMMON::Pyramid;
use COMMON::Script;
use COMMON::DataSourceLoader;
use COMMON::DataSource;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw() ] );
our @EXPORT_OK   = ( @{$EXPORT_TAGS{'all'}} );
our @EXPORT      = qw();

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

# Constant: STORAGETYPES
# Define allowed values for attribute storage type.
my @STORAGETYPES;

################################################################################

BEGIN {}
INIT {
    @STORAGETYPES = ("FILE", "CEPH", "S3");
}
END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

Forest constructor. Bless an instance.

Parameters (list):
    pyramid - <BE4::Pyramid> or <BE4CEPH::Pyramid> or <BE4S3::Pyramid> - Contains output format specifications, needed by generations command's.
    DSL - <DataSourceLoader> - Contains one or several data sources
    params_process - hash - Informations for scripts
|               job_number - integer - Parallelization level
|               path_temp - string - Temporary directory
|               path_temp_common - string - Common temporary directory
|               path_shell - string - Script directory
    storageType - string - Pyramid final storage type : FS, CEPH, S3 or SWIFT

See also:
    <_init>, <_load>
=cut
sub new {
    my $class = shift;
    my $pyramid = shift;
    my $DSL = shift;
    my $params_process = shift;
    my $storageType = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        pyramid     => undef,
        commands    => undef,
        graphs      => [],
        scripts     => [],
        splitNumber => undef,
        storageType => undef
    };

    bless($this, $class);

    # it's an object and it's mandatory !
    if (! defined $pyramid || ref ($pyramid) ne "COMMON::Pyramid") {
        ERROR("We need a COMMON::Pyramid to create a Forest");
        return undef;
    }
    $this->{pyramid} = $pyramid;
    
    # it's an object and it's mandatory !
    if (! defined $DSL || ref ($DSL) ne "COMMON::DataSourceLoader") {
        ERROR("We need a COMMON::DataSourceLoader to create a Forest");
        return undef;
    }

    if (! defined $params_process) {
        ERROR("We need process' parameters to create a Forest");
        return undef;
    }

    if (! defined COMMON::Array::isInArray($storageType, @STORAGETYPES) ) {
        ERROR("Forest's storage type is undefined or not valid !");
        return undef;
    }
    $this->{storageType} = $storageType;
    
    # load. class
    return undef if (! $this->_load($DSL, $params_process) );
    
    INFO (sprintf "Graphs' number : %s",scalar @{$this->{graphs}});

    return $this;
}


=begin nd
Function: _load

Creates a <NNGraph> or a <QTree> object per data source and a <Commands> object. Using a QTree is faster but it does'nt match all cases.

All differences between different kinds of graphs are handled in respective classes, in order to be imperceptible for users.

Only scripts creation and initial organization are managed by the forest.

Parameters (list):
    pyramid - <Pyramid> - Contains output format specifications, needed by generations command's.
    DSL - <DataSourceLoader> - Contains one or several data sources
    params_process - hash - Informations for scipts, where to write them, temporary directory to use...
|               job_number - integer - Parallelization level
|               path_temp - string - Temporary directory
|               path_temp_common - string - Common temporary directory
|               path_shell - string - Script directory
    storageType - string - Pyramid final storage type : FS, CEPH, S3 or SWIFT

=cut
sub _load {
    my $this = shift;
    my $DSL = shift;
    my $params_process = shift;

    my $dataSources = $DSL->getDataSources();
    my $TMS = $this->{pyramid}->getTileMatrixSet();
    my $isQTree = $TMS->isQTree();
    
    ######### PARAM PROCESS ###########
    
    my $splitNumber = $params_process->{job_number};
    my $tempDir = $params_process->{path_temp};
    my $commonTempDir = $params_process->{path_temp_common};
    my $scriptDir = $params_process->{path_shell};

    if (! defined $splitNumber) {
        ERROR("Parameter required : 'job_number' in section 'Process' !");
        return FALSE;
    }
    $this->{splitNumber} = $splitNumber;

    if (! defined $tempDir) {
        ERROR("Parameter required : 'path_temp' in section 'Process' !");
        return FALSE;
    }

    if (! defined $commonTempDir) {
        ERROR("Parameter required : 'path_temp_common' in section 'Process' !");
        return FALSE;
    }

    if (! defined $scriptDir) {
        ERROR("Parameter required : 'path_shell' in section 'Process' !");
        return FALSE;
    }

    # Ajout du nom de la pyramide aux dossiers temporaires (pour distinguer de ceux des autres générations)
    $tempDir = File::Spec->catdir($tempDir,$this->{pyramid}->getName() );
    $commonTempDir = File::Spec->catdir($commonTempDir,$this->{pyramid}->getName() );

    ############# PROCESS #############

    $this->{commands} = COMMON::ShellCommands->new($this->{pyramid}, $params_process->{use_masks});
    if (! defined $this->{commands}) {
        ERROR ("Can not load Commands !");
        return FALSE;
    }
    
    ############# SCRIPTS #############
    # We create COMMON::Script objects and initialize them (header)

    my $functions = $this->{commands}->getConfiguredFunctions();

    if ($isQTree) {
        #### QTREE CASE

        for (my $i = 0; $i <= $this->getSplitNumber; $i++) {
            my $scriptID = sprintf "SCRIPT_%s",$i;
            my $executedAlone = FALSE;

            if ($i == 0) {
                $scriptID = "SCRIPT_FINISHER";
                $executedAlone = TRUE;
            }

            my $script = COMMON::Script->new({
                id => $scriptID,
                tempDir => $tempDir,
                commonTempDir => $commonTempDir,
                scriptDir => $scriptDir,
                executedAlone => $executedAlone
            });

            $script->prepare($this->{pyramid}, $functions);

            push @{$this->{scripts}}, $script;
        }
    } else {
        #### GRAPH CASE

        # Boucle sur les levels et sur le nb de scripts/jobs
        # On commence par les finishers
        # On continue avec les autres scripts, par level
        for (my $i = $this->{pyramid}->getBottomOrder - 1; $i <= $this->{pyramid}->getTopOrder; $i++) {
            for (my $j = 1; $j <= $this->getSplitNumber; $j++) {
                my $scriptID;
                if ($i == $this->{pyramid}->getBottomOrder - 1) {
                    $scriptID = sprintf "SCRIPT_FINISHER_%s", $j;
                } else {
                    my $levelID = $this->getPyramid()->getIDfromOrder($i);
                    $scriptID = sprintf "LEVEL_%s_SCRIPT_%s", $levelID, $j;
                }

                my $script = COMMON::Script->new({
                    id => $scriptID,
                    tempDir => $tempDir,
                    commonTempDir => $commonTempDir,
                    scriptDir => $scriptDir,
                    executedAlone => FALSE
                });

                $script->prepare($this->{pyramid}, $functions);

                push @{$this->{scripts}},$script;
            }
        }

        # Le SUPER finisher
        my $script = COMMON::Script->new({
            id => "SCRIPT_FINISHER",
            tempDir => $tempDir,
            commonTempDir => $commonTempDir,
            scriptDir => $scriptDir,
            executedAlone => TRUE
        });

        $script->prepare($this->{pyramid}, $functions);

        push @{$this->{scripts}},$script;
    }
    
    ######## PROCESS (suite) #########

    $this->{commands}->setConfDir($this->{scripts}[0]->getMntConfDir(), $this->{scripts}[0]->getDntConfDir());
    
    ############# GRAPHS #############

    foreach my $datasource (@{$dataSources}) {
        
        # Now, if datasource contains a WMS service, we have to use it
        
        # Creation of QTree or NNGraph object
        my $graph = undef;
        if ($isQTree) {
            $graph = COMMON::QTree->new($this, $datasource, $this->{pyramid}, $this->{commands});
        } else {
            $graph = COMMON::NNGraph->new($this,$datasource, $this->{pyramid}, $this->{commands});
        };
                
        if (! defined $graph) {
            ERROR(sprintf "Can not create a graph for datasource with bottom level %s !",$datasource->getBottomID);
            return FALSE;
        }
        
        push @{$this->{graphs}},$graph;
    }

    return TRUE;
}


####################################################################################################
#                                  Group: Graphs tools                                             #
####################################################################################################

=begin nd
Function: containsNode

Returns a boolean : TRUE if the node belong to this forest, FALSE otherwise (if a parameter is not defined too).

Parameters (list):
    level - string - Level ID of the node we want to know if it is in the forest.
    i - integer - Column of the node we want to know if it is in the forest.
    j - integer - Row of the node we want to know if it is in the forest.
=cut
sub containsNode {
    my $this = shift;
    my $level = shift;
    my $i = shift;
    my $j = shift;

    return FALSE if (! defined $level || ! defined $i || ! defined $j);
    
    foreach my $graph (@{$this->{graphs}}) {
        return TRUE if ($graph->containsNode($level,$i,$j));
    }
    
    return FALSE;
}

=begin nd
Function: computeGraphs

Computes each <NNGraph> or <QTree> one after the other and closes scripts to finish.

See Also:
    <NNGraph::computeYourself>, <QTree::computeYourself>
=cut
sub computeGraphs {
    my $this = shift;

    
    my $graphInd = 1;
    my $graphNumber = scalar @{$this->{graphs}};
    
    foreach my $graph (@{$this->{graphs}}) {
        if (! $graph->computeYourself) {
            ERROR(sprintf "Cannot compute graph $graphInd/$graphNumber");
            return FALSE;
        }
        INFO("Graph $graphInd/$graphNumber computed");
        DEBUG($graph->exportForDebug);
        $graphInd++;
    }
    
    foreach my $script (@{$this->{scripts}}) {
        $script->close;
    }
    
    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getGraphs
sub getGraphs {
    my $this = shift;
    return $this->{graphs}; 
}

# Function: getStorageType
sub getStorageType {
    my $this = shift;
    return $this->{storageType}; 
}

# Function: getPyramid
sub getPyramid {
    my $this = shift;
    return $this->{pyramid}; 
}

# Function: getScripts
sub getScripts {
    my $this = shift;
    return $this->{scripts};
}

=begin nd
Function: getScript

Parameters (list):
    ind - integer - Script's indice in the array
=cut
sub getScript {
    my $this = shift;
    my $ind = shift;
    
    return $this->{scripts}[$ind];
}

=begin nd
Function: getWeightOfScript

Parameters (list):
    ind - integer - Script's indice in the array
=cut 
sub getWeightOfScript {
    my $this = shift;
    my $ind = shift;
    
    return $this->{scripts}[$ind]->getWeight;
}

=begin nd
Function: setWeightOfScript

Parameters (list):
    ind - integer - Script's indice in the array
    weight - integer - Script's weight to set
=cut
sub setWeightOfScript {
    my $this = shift;
    my $ind = shift;
    my $weight = shift;
    
    $this->{scripts}[$ind]->setWeight($weight);
}

# Function: getSplitNumber
sub getSplitNumber {
    my $this = shift;
    return $this->{splitNumber};
}

####################################################################################################
#                                Group: Export methods                                             #
####################################################################################################

=begin nd
Function: exportForDebug

Returns all informations about the forest. Useful for debug.

Example:
    (start code)
    (end code)
=cut
sub exportForDebug {
    my $this = shift ;
    
    my $export = "";
    
    $export .= sprintf "\n Object COMMON::Forest :\n";

    $export .= "\t Graph :\n";
    $export .= sprintf "\t Number of graphs in the forest : %s\n", scalar @{$this->{graphs}};
    
    $export .= "\t Scripts :\n";
    $export .= sprintf "\t Number of split : %s\n", $this->{splitNumber};
    $export .= sprintf "\t Number of script : %s\n", scalar @{$this->{scripts}};
    
    return $export;
}

1;
__END__
