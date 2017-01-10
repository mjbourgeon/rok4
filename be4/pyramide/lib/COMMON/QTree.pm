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
File: QTree.pm

Class: COMMON::QTree

Representation of a quad tree image pyramid : pyramid's image = <COMMON::Node>

(see QTreeTMS.png)

To generate this kind of graph, we use :
    - *jobNumber* scripts : to generate and format image from the bottom level to the cut level.
    - 1 script (finisher) : to generate and format image from the cut level to the top level.

=> *jobNumber + 1* scripts

Organization in the <Forest> scripts' array :

(see script_QTree.png)

As a tree, a node has just one parent. As a QUAD tree, the parent belong to the above level and a node has 4 children at most.

Link between a node and his children or his father is trivial, and needn't to be store :
    - To know parent's indices, we divide own indices by 2 (and keep floor), and the level is the just above one
    - To know 4 possible chlidren's, in the just below level :
|        i*2, j*2
|        i*2, j*2 + 1
|        i*2 + 1, j*2
|        i*2 + 1, j*2 + 1

Using:
    (start code)
    use COMMON::QTree;

    # QTree object creation
    my $objQTree = COMMON::QTree->new($objForest, $objDataSource, $objPyramid, $objCommands);

    ...

    # Fill each node with computing code, weight, share job on scripts
    $objQTree->computeYourself();
    (end code)

Attributes:
    forest - <COMMON::Forest> - Forest which this tree belong to.
    pyramid - <COMMON::Pyramid> - Pyramid linked to this tree.
    commands - <COMMON::ShellCommands> - Command to use to generate images.
    datasource - <COMMON::DataSource> - Data source to use to define bottom level nodes and generate them.

    bbox - double array - Datasource bbox, [xmin,ymin,xmax,ymax], in TMS' SRS
    nodes - <COMMON::Node> hash - Structure is:
        (start code)
        level1 => {
           c1_r2 => n1,
           c2_r2 => n2,
           c3_r2 => n3, ...}
        level2 => {
           c1_r2 => n4,
           c2_r2 => n5, ...}

        cX : node's column
        rX : node's row
        nX : COMMON::Node
        (end code)

    cutLevelID - string - Cut level identifiant. To parallelize work, split scripts will generate cache from the bottom to this level. Script finisher will be generate from this above, to top.
    bottomID - string - Bottom level identifiant
    topID - string - Top level identifiant
=cut

################################################################################

package COMMON::QTree;

use strict;
use warnings;

use Math::BigFloat;
use Data::Dumper;

use COMMON::DataSource;
use COMMON::Node;
use COMMON::Pyramid;
use COMMON::Array;
use COMMON::ShellCommands;

use Log::Log4perl qw(:easy);

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

################################################################################

BEGIN {}
INIT {}
END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

QTree constructor. Bless an instance.

Parameters (list):
    objForest - <COMMON::Forest> - Forest which this tree belong to
    objSrc - <COMMON::DataSource> - Datasource which determine bottom level nodes
    objPyr - <COMMON::Pyramid> - Pyramid linked to this tree
    objCommands - <COMMON::ShellCommands> - Commands to use to generate pyramid's images

See also:
    <_init>, <_load>
=cut
sub new {
    my $class = shift;
    my $objForest = shift;
    my $objSrc = shift;
    my $objPyr = shift;
    my $objCommands = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        # in
        forest    => undef,
        pyramid    => undef,
        commands    => undef,
        datasource => undef,
        # out
        bbox => [],
        nodes => {},
        # levels
        cutLevelID    => undef,
        bottomID => undef,
        topID    => undef,
    };

    bless($this, $class);

    # mandatory parameters !
    if (! defined $objForest || ref ($objForest) ne "COMMON::Forest") {
        ERROR("We need a COMMON::Forest to create a QTree");
        return FALSE;
    }
    if (! defined $objSrc || ref ($objSrc) ne "COMMON::DataSource") {
        ERROR("We need a COMMON::DataSource to create a QTree");
        return FALSE;
    }
    if (! defined $objPyr || ref ($objPyr) ne "COMMON::Pyramid") {
        ERROR("We need a COMMON::Pyramid to create a QTree");
        return FALSE;
    }
    if (! defined $objCommands || ref ($objCommands) ne "COMMON::ShellCommands") {
        ERROR("We need a COMMON::ShellCommands to create a QTree");
        return FALSE;
    }

    # init. params   
    $this->{forest} = $objForest; 
    $this->{pyramid} = $objPyr;
    $this->{datasource} = $objSrc; 
    $this->{commands} = $objCommands;

    # load 
    return undef if (! $this->_load());

    return $this;
}

=begin nd
Function: _load

Determines all nodes from the bottom level to the top level, thanks to the data source.
=cut
sub _load {
    my $this = shift;

    # initialisation pratique:
    my $tms = $this->{pyramid}->getTileMatrixSet();
    my $src = $this->{datasource};
    
    # récupération d'information dans la source de données
    $this->{topID} = $this->{datasource}->getTopID;
    $this->{bottomID} = $this->{datasource}->getBottomID;

    # initialisation de la transfo de coord du srs des données initiales vers
    # le srs de la pyramide. Si les srs sont identiques on laisse undef.
    my $ct = undef;
    
    if ($tms->getSRS() ne $src->getSRS()){
        $ct = COMMON::ProxyGDAL::coordinateTransformationFromSpatialReference($src->getSRS(), $tms->getSRS());
        if (! defined $ct) {
            ERROR(sprintf "Cannot instanciate the coordinate transformation object %s->%s", $src->getSRS(), $tms->getSRS());
            return FALSE;
        }
    }

    # identifier les noeuds du niveau de base à mettre à jour et les associer aux images sources:
    if ( ! $this->identifyBottomNodes($ct) ) {
        ERROR(sprintf "Cannot determine bottom tiles for the level %s",$src->getBottomID);
        return FALSE;
    }

    INFO(sprintf "Number of cache images to the bottom level (%s) : %d",
        $this->{bottomID},scalar keys(%{$this->{nodes}{$this->{bottomID}}}));

    # identifier les noeuds des niveaux supérieurs
    if ( ! $this->identifyAboveNodes() ) {
        ERROR(sprintf "Cannot determine above levels' tiles.");
        return FALSE;
    }
         
    return TRUE;
}

####################################################################################################
#                          Group: Nodes determination methods                                      #
####################################################################################################

=begin nd
Function: identifyBottomNodes

Calculate all nodes in bottom level concerned by the datasource (tiles which touch the data source extent or provided in a file).

Parameters (list):
    ct - <Geo::OSR::CoordinateTransformation> - To convert data extent or images' bbox.
=cut
sub identifyBottomNodes {
    my $this = shift;
    my $ct = shift;
    
    my $bottomID = $this->{bottomID};
    my $tm = $this->{pyramid}->getTileMatrixSet->getTileMatrix($bottomID);
    if (! defined $tm) {
        ERROR(sprintf "Impossible de récupérer le TM à partir de %s (bottomID) et du TMS : %s.",$bottomID,$this->getPyramid()->getTileMatrixSet()->exportForDebug());
        return FALSE;
    };
    my $datasource = $this->{datasource};
    my ($TPW,$TPH) = ($this->{pyramid}->getTilesPerWidth,$this->{pyramid}->getTilesPerHeight);
    
    if ($datasource->hasImages() ) {
        # We have real data as source. Images determine bottom tiles
        my @images = $datasource->getImages();
        foreach my $objImg (@images){
            # On reprojette l'emprise si nécessaire
            my @bbox = $objImg->convertBBox($ct); # [xMin, yMin, xMax, yMax]
            if ($bbox[0] == 0 && $bbox[2] == 0) {
                ERROR(sprintf "Impossible to compute BBOX for the image '%s'. Probably limits are reached !", $objImg->getName());
                return FALSE;
            }
            
            $this->updateBBox(@bbox);
            
            # On divise les coord par la taille des dalles de cache pour avoir les indices min et max en x et y
            my ($rowMin, $rowMax, $colMin, $colMax) = $tm->bboxToIndices(@bbox,$TPW,$TPH);
            
            for (my $col = $colMin; $col<= $colMax; $col++){
                for (my $row = $rowMin; $row<= $rowMax; $row++){
                    my $nodeKey = sprintf "%s_%s", $col, $row;

                    if ( $datasource->hasHarvesting() ) {
                        # we use WMS service to generate this leaf
                        if (exists $this->{nodes}->{$bottomID}->{$nodeKey}) {
                            # This Node already exists
                            next;
                        }
                        # Create a new Node
                        my $node = COMMON::Node->new({
                            col => $col,
                            row => $row,
                            tm => $tm,
                            graph => $this,
                            type => $this->{forest}->getStorageType()
                        });
                        if (! defined $node) { 
                            ERROR(sprintf "Cannot create Node for level %s, indices %s,%s.", $this->{bottomID}, $col, $row);
                            return FALSE;
                        }
                        $this->{nodes}->{$bottomID}->{$nodeKey} = $node;
                    } else {
                        # we use images to generate this leaf
                        if (! exists $this->{nodes}->{$bottomID}->{$nodeKey}) {

                            # Create a new Node
                            my $node = COMMON::Node->new({
                                col => $col,
                                row => $row,
                                tm => $tm,
                                graph => $this,
                                type => $this->{forest}->getStorageType()
                            });
                            if (! defined $node) { 
                                ERROR(sprintf "Cannot create Node for level %s, indices %s,%s.", $this->{bottomID}, $col, $row);
                                return FALSE;
                            }
                            
                            $this->{nodes}->{$bottomID}->{$nodeKey} = $node;
                        }

                        $this->{nodes}->{$bottomID}->{$nodeKey}->addGeoImages($objImg);
                    }
                }
            }
        }
    } elsif (defined $datasource->getExtent() ) {
        # We have just a WMS service as source. We use extent to determine bottom tiles
        my $convertExtent = COMMON::ProxyGDAL::getConvertedGeometry($datasource->getExtent(), $ct);
        if (! defined $convertExtent) {
            ERROR(sprintf "Cannot convert extent for the datasource");
            return FALSE;
        }

        # Pour éviter de balayer une bbox trop grande, on récupère la bbox de chaque partie de la - potentiellement multi - géométrie
        my $bboxes = COMMON::ProxyGDAL::getBboxes($convertExtent);

        foreach my $bb (@{$bboxes}) {
        
            $this->updateBBox(@{$bb});

            my ($rowMin, $rowMax, $colMin, $colMax) = $tm->bboxToIndices(@{$bb},$TPW,$TPH);
            
            for (my $col = $colMin; $col<= $colMax; $col++){
                for (my $row = $rowMin; $row<= $rowMax; $row++){
            
                    my ($xmin,$ymin,$xmax,$ymax) = $tm->indicesToBbox($col, $row, $TPW, $TPH);

                    my $OGRtile = COMMON::ProxyGDAL::geometryFromBbox($xmin,$ymin,$xmax,$ymax);

                    if (COMMON::ProxyGDAL::isIntersected($OGRtile, $convertExtent)) {
                        my $nodeKey = sprintf "%s_%s", $col, $row;
                        # Create a new Node
                        my $node = COMMON::Node->new({
                            col => $col,
                            row => $row,
                            tm => $tm,
                            graph => $this,
                            type => $this->{forest}->getStorageType()
                        });
                        if (! defined $node) { 
                            ERROR(sprintf "Cannot create Node for level %s, indices %s,%s.", $this->{bottomID}, $col, $row);
                            return FALSE;
                        }
                        $this->{nodes}->{$bottomID}->{$nodeKey} = $node;
                    }
                }
            }
        }
    } else {
        # On a un fichier qui liste les indices des dalles à générer
        my $listfile = $datasource->getList();
        
        open(LISTIN, "<$listfile") or do {
            ERROR(sprintf "Cannot open the file containing the list of image for the bottom level ($listfile)");
            return FALSE;            
        };
        
        while (my $line = <LISTIN>) {
            chomp($line);
            
            my ($col, $row) = split(/,/, $line);
            
            my $nodeKey = sprintf "%s_%s", $col, $row;
            
            if (exists $this->{nodes}->{$bottomID}->{$nodeKey}) {
                # This Node already exists
                next;
            }
            
            my ($xmin,$ymin,$xmax,$ymax) = $tm->indicesToBbox($col,$row,$TPW,$TPH);

            $this->updateBBox($xmin,$ymin,$xmax,$ymax);
            
            # Create a new Node
            my $node = COMMON::Node->new({
                col => $col,
                row => $row,
                tm => $tm,
                graph => $this,
                type => $this->{forest}->getStorageType()
            });
            if (! defined $node) { 
                ERROR(sprintf "Cannot create Node for level %s, indices %s,%s.", $this->{bottomID}, $col, $row);
                return FALSE;
            }
            $this->{nodes}->{$bottomID}->{$nodeKey} = $node;
        }
        
        close(LISTIN);
    }
  
    return TRUE;  
}

=begin nd
Function: identifyAboveNodes

Calculate all nodes in above levels. We generate a above level node if one or more children are generated.

(see aboveNodes_QTree.png)
=cut
sub identifyAboveNodes {
    my $this = shift;
    
    # initialisation pratique:
    my $tms = $this->{pyramid}->getTileMatrixSet();
    my $src = $this->{datasource};
    
    # Calcul des branches à partir des feuilles
    for (my $i = $src->getBottomOrder; $i <= $src->getTopOrder; $i++){
        my $levelID = $tms->getIDfromOrder($i);

        # pyramid's limits update : we store data's limits in the pyramid's levels
        $this->{pyramid}->updateTMLimits($levelID, @{$this->{bbox}});

        foreach my $node ($this->getNodesOfLevel($levelID)) {
            
            if ($i != $src->getTopOrder) {
                my $aboveLevelID = $tms->getIDfromOrder($i+1);
                my $parentNodeKey = int($node->getCol/2)."_".int($node->getRow/2);
                if (exists $this->{nodes}->{$aboveLevelID}->{$parentNodeKey}) {
                    # This Node already exists
                    next;
                }
                # Create a new Node
                my $node = COMMON::Node->new({
                    col => int($node->getCol/2),
                    row => int($node->getRow/2),
                    tm => $tms->getTileMatrix($aboveLevelID),
                    graph => $this,
                    type => $this->{forest}->getStorageType()
                });
                if (! defined $node) { 
                    ERROR(sprintf "Cannot create Node for level %s, indices %s,%s.",
                          $aboveLevelID, int($node->getRow/2), int($node->getRow/2));
                    return FALSE;
                }
                $this->{nodes}->{$aboveLevelID}->{$parentNodeKey} = $node;
            }
        }

        DEBUG(sprintf "Number of cache images by level (%s) : %d",
              $levelID, scalar keys(%{$this->{nodes}{$levelID}}));
    }
    
    return TRUE;  
}

####################################################################################################
#                                   Group: Compute methods                                         #
####################################################################################################

=begin nd
Function: computeYourself

Determine codes and weights for each node of the current QTree, and share work on scripts, so as to optimize execution time.

Three steps:
    - we add weights (own and accumulated) and commands for each node : <computeBranch>
    (see weights.png)
    - we determine the cut level, to distribute fairly work : <shareNodesOnJobs>
    - we write commands in the script associated to the node : <writeBranchCode> and <writeTopCode>
=cut
sub computeYourself {
    my $this = shift;

    
    my @topLevelNodes = $this->getNodesOfTopLevel;
    
    # ----------------------- WEIGHT AND CODE ---------------------------
    # Pondération de l'arbre en fonction des opérations à réaliser et écriture des commandes dans les noeuds
    foreach my $topNode (@topLevelNodes) {
        if (! $this->computeBranch($topNode)) {
            ERROR(sprintf "Can not weight the node of the top level '%s'!", $topNode->getWorkBaseName);
            return FALSE;
        }
    }
    
    # -------------------------- SHARING --------------------------------
    # Détermination du cutLevel optimal et répartition des noeuds sur les jobs,
    # en tenant compte du fait qu'ils peuvent déjà contenir du travail, du fait
    # de la pluralité des arbres à traiter.
    
    $this->shareNodesOnJobs();

    if (! defined $this->{cutLevelID}) {
        ERROR("Impssible to determine the cut level !");
        return FALSE;
    }
    INFO (sprintf "CutLevel : %s", $this->{cutLevelID});

    # ----------------- PRECISE LEVELS IN SCRIPTS -----------------------
    my $levelsExport = $this->exportLevelsForScript();
    for (my $i = 0; $i <= $this->{forest}->getSplitNumber(); $i++) {
        $this->{forest}->getScript($i)->write($levelsExport);
    }

    # -------------------------- WRITTING -------------------------------
    
    foreach my $topNode (@topLevelNodes) {
        if ($this->getTopID ne $this->getCutLevelID) {
            $topNode->setScript($this->getScriptFinisher());
        }
        
        $this->writeCode($topNode);
    }
    
    return TRUE;
}

=begin nd
Function: computeBranch

Recursive method, which allow to browse tree downward.

2 cases.
    - the node belong to the bottom level -> <computeBottomImage>
    - the node does not belong to the bottom level -> <computeBranch> on each child, then <computeAboveImage>

Parameters (list):
    node - <COMMON::Node> - Node to compute.
=cut
sub computeBranch {
    
    my $this = shift;
    my $node = shift;

    my $weight = 0;

    
    my $res = '';
    my @childList = $this->getChildren($node);
    if (scalar @childList == 0){
        if (! $this->computeBottomImage($node)) {
            ERROR(sprintf "Cannot compute the bottom image : %s",$node->getWorkName());
            return FALSE;
        }
        return TRUE;
    }
    foreach my $n (@childList) {
        
        if (! $this->computeBranch($n)) {
            ERROR(sprintf "Cannot compute the branch from node %s", $node->getWorkBaseName());
            return FALSE;
        }
        $weight += $n->getAccumulatedWeight;
    }

    if (! $this->computeAboveImage($node)) {
        ERROR(sprintf "Cannot compute the above image : %s", $node->getWorkName());
        return FALSE;
    }

    $node->setAccumulatedWeight($weight);

    return TRUE;
}

=begin nd
Function: computeBottomImage

Treats a bottom node : determine code or weight.

2 cases:
    - lossless compression and images as data -> <Commands::mergeNtiff>
    - reprojection or lossy compression or just a WMS service as data -> <Commands::wms2work>

Then the work image is formatted and move to the final place thanks to <Commands::work2cache>.

Parameters (list):
    node - <COMMON::Node> - Bottom level's node, to treat.
    
=cut
sub computeBottomImage {
    
    my $this = shift;
    my $node = shift;

    
    # Temporary weight and code
    my ($c,$w);
    # Final weight and code
    my $weight  = 0;
    my $code  = "\n";
    
    if ($this->getDataSource->hasHarvesting) {
        # Datasource has a WMS service : we have to use it
        ($c,$w) = $this->{commands}->wms2work($node,$this->getDataSource->getHarvesting());
        if (! defined $c) {
            ERROR(sprintf "Cannot harvest image for node %s",$node->getWorkBaseName());
            return FALSE;
        }
        
        $code .= $c;
        $weight += $w;
    } else {    
        ($c,$w) = $this->{commands}->mergeNtiff($node);
        if ($w == -1) {
            ERROR(sprintf "Cannot compose mergeNtiff command for the node %s.",$node->getWorkBaseName());
            return FALSE;
        }
        $code .= $c;
        $weight += $w;
    }

    ($c,$w) = $this->{commands}->work2cache($node, "\${TMP_DIR}");
    $code .= $c;
    $weight += $w;

    $node->setOwnWeight($weight);
    $node->setAccumulatedWeight(0);
    $node->setCode($code);

    return TRUE;
}

=begin nd
Function: computeAboveImage

Treats an above node (different to the bottom level) : determine code or weight.

To generate an above node, we use <Commands::merge4tiff> with children.

Then the work image is formatted and move to the final place thanks to <Commands::work2cache>.

Parameters (list):
    node - <COMMON::Node> - Above level's node, to treat.
=cut
sub computeAboveImage {
    
    my $this = shift;
    my $node = shift;


    # Temporary weight and code
    my ($c,$w);
    # Final weight and code
    my $weight  = 0;
    my $code  = "\n";
    
    # Maintenant on constitue la liste des images à passer à merge4tiff.
    ($c,$w) = $this->{commands}->merge4tiff($node);
    if ($w == -1) {
        ERROR(sprintf "Cannot compose merge4tiff command for the node %s.",$node->getWorkBaseName);
        return FALSE;
    }
    $code .= $c;
    $weight += $w;

    ($c,$w) = $this->{commands}->work2cache($node,"\${TMP_DIR}");
    $code .= $c;
    $weight += $w;

    $node->setOwnWeight($weight);
    $node->setCode($code);

    return TRUE;
}

####################################################################################################
#                                   Group: Writer methods                                          #
####################################################################################################

=begin nd
Function: writeCode

Recursive method, which allow to browse tree (downward) and write commands in associated node's script.

Parameters (list):
    node - <COMMON::Node> - Node whose code is written.
=cut
sub writeCode {
    my $this = shift;
    my $node = shift;



    my @childList = $this->getChildren($node);

    # Le noeud est une feuille
    if (scalar @childList == 0){
        $node->writeInScript();
        return TRUE;
    }

    # Le noeud a des enfants
    foreach my $n (@childList) {
        if ($n->getLevel() ne $this->getCutLevelID()) {
            $n->setScript($node->getScript());
        }
        $this->writeCode($n);
    }
    
    $node->writeInScript();

    return TRUE;
}

####################################################################################################
#                                  Group: Cut level methods                                        #
####################################################################################################

=begin nd
Function: shareNodesOnJobs

Determine the cutLevel to optimize sharing into scripts and execution time.
(see scripts.png)

For each level:
    - we sort nodes by descending accumulated weight
    - we deal nodes on scripts. Not a round robin distribution, but we assign node generation to the lighter script.
    - we add the heavier weight and the finisher weight : we obtain the worst weight and we memorized it to finally keep the smaller worst weight.

The cut level could be the bottom level (splits only generate bottom level nodes) or the top level (finisher script do nothing).

To manipulate weights array, we use the tool class <Array>.
=cut
sub shareNodesOnJobs {
    my $this = shift;


    my $tms = $this->{pyramid}->getTileMatrixSet;
    my $splitNumber = $this->{forest}->getSplitNumber;
    
    my $optimalWeight = undef;
    my $cutLevelID = undef;
    
    my @INIT_WEIGHTS = undef;
    my @jobsWeights = undef;

    # calcul du poids total de l'arbre : c'est la somme des poids cumulé des noeuds du topLevel
    my $wholeTreeWeight = 0;
    my @topLevelNodeList = $this->getNodesOfTopLevel;
    foreach my $node (@topLevelNodeList) {
        $wholeTreeWeight += $node->getAccumulatedWeight;
    }
    
    for (my $i = $this->getBottomOrder(); $i <= $this->getTopOrder(); $i++) {
        my $levelID = $tms->getIDfromOrder($i);
        my @levelNodeList = $this->getNodesOfLevel($levelID);
        
        @levelNodeList = sort {$b->getAccumulatedWeight <=> $a->getAccumulatedWeight} @levelNodeList;

        my @TMP_WEIGHTS;
        for (my $j = 0; $j <= $splitNumber; $j++) {
            # On initialise les poids avec ceux des scripts (peuvent ne pas être vides, si multi-sources)
            $TMP_WEIGHTS[$j] = $this->{forest}->getWeightOfScript($j);
        }
        
        my $finisherWeight = $wholeTreeWeight;
        
        for (my $j = 0; $j < scalar @levelNodeList; $j++) {
            my $scriptInd = COMMON::Array::minArrayIndex(1,@TMP_WEIGHTS);
            my $nodeWeight = $levelNodeList[$j]->getAccumulatedWeight;
            $TMP_WEIGHTS[$scriptInd] += $nodeWeight;
            $finisherWeight -= $nodeWeight;
            $levelNodeList[$j]->setScript($this->{forest}->getScript($scriptInd));
        }
        
        # on additionne le poids du job le plus "lourd" et le poids du finisher pour quantifier le
        # pire temps d'exécution
        $TMP_WEIGHTS[0] += $finisherWeight;
        my $worstWeight = COMMON::Array::maxArrayValue(1,@TMP_WEIGHTS) + $finisherWeight;
        
        DEBUG(sprintf "For the level $levelID, the worst weight is $worstWeight.");

        # on compare ce pire des cas avec celui obtenu jusqu'ici. S'il est plus petit, on garde ce niveau comme
        # cutLevel (a priori celui qui optimise le temps total de la génération de la pyramide).
        if (! defined $optimalWeight || $worstWeight < $optimalWeight) {
            $optimalWeight = $worstWeight;
            $cutLevelID = $levelID;
            @jobsWeights = @TMP_WEIGHTS;
            DEBUG (sprintf "New cutLevel found : %s (worstWeight : %s)",$levelID,$optimalWeight);
        }
    }
    
    # We store results in array references
    for (my $i = 0; $i <= $splitNumber; $i++) {
        $this->{forest}->setWeightOfScript($i,$jobsWeights[$i]);
    }

    $this->{cutLevelID} = $cutLevelID;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getDataSource
sub getDataSource {
    my $this = shift;
    return $this->{datasource};
}

# Function: getPyramid
sub getPyramid {
    my $this = shift;
    return $this->{pyramid};
}

# Function: getCutLevelID
sub getCutLevelID {
    my $this = shift;
    return $this->{cutLevelID};
}

# Function: getTopID
sub getTopID {
    my $this = shift;
    return $this->{topID};
}

# Function: getTopOrder
sub getTopOrder {
    my $this = shift;
    return $this->{pyramid}->getTileMatrixSet->getOrderfromID($this->{topID});
}

# Function: getBottomOrder
sub getBottomOrder {
    my $this = shift;
    return $this->{pyramid}->getTileMatrixSet->getOrderfromID($this->{bottomID});
}

# Function: getScriptFinisher
sub getScriptFinisher {
    my $this = shift;
    return $this->{forest}->getScript(0); 
}

=begin nd
Function: containsNode

Returns a boolean : TRUE if the node belong to this tree, FALSE otherwise (if a parameter is not defined too).

Parameters (list):
    level - string - Level ID of the node we want to know if it is in the quad tree.
    i - integer - Column of the node we want to know if it is in the quad tree.
    j - integer - Row of the node we want to know if it is in the quad tree.
=cut
sub containsNode {
    my $this = shift;
    my $level = shift;
    my $i = shift;
    my $j = shift;

    return FALSE if (! defined $level || ! defined $i || ! defined $j);
    
    my $nodeKey = $i."_".$j;
    return (exists $this->{nodes}->{$level}->{$nodeKey});
}

=begin nd
Function: updateBBox

Compare provided and stored extrems coordinates and update values.

Parameters (list):
    xmin, ymin, xmax, ymax - double - New coordinates to compare with current bbox.
=cut
sub updateBBox {
    my $this = shift;
    my ($xmin,$ymin,$xmax,$ymax) = @_;

    
    if (! defined $this->{bbox}[0] || $xmin < $this->{bbox}[0]) {$this->{bbox}[0] = $xmin;}
    if (! defined $this->{bbox}[1] || $ymin < $this->{bbox}[1]) {$this->{bbox}[1] = $ymin;}
    if (! defined $this->{bbox}[2] || $xmax > $this->{bbox}[2]) {$this->{bbox}[2] = $xmax;}
    if (! defined $this->{bbox}[3] || $ymax > $this->{bbox}[3]) {$this->{bbox}[3] = $ymax;}
}

=begin nd
Function: getPossibleChildren

Returns a <COMMON::Node> array, containing children (length is always 4, with undefined value for children which don't exist), an empty array if the node is a leaf.

Warning:
    Do not mistake with <getChildren>

Parameters (list):
    node - <COMMON::Node> - Node whose we want to know possible children.
=cut
sub getPossibleChildren {
    my $this = shift;
    my $node = shift;
    
    my @res;
    if ($node->getLevel eq $this->{bottomID}) {
        return @res;
    }
    
    my $lowerLevelID = $this->{pyramid}->getTileMatrixSet->getBelowLevelID($node->getLevel);
    
    for (my $j=0; $j<=1; $j++){
        for (my $i=0; $i<=1; $i++){
            my $nodeKey = sprintf "%s_%s",$node->getCol*2+$i, $node->getRow*2+$j;
            if (exists $this->{nodes}->{$lowerLevelID}->{$nodeKey}) {
                push @res, $this->{nodes}->{$lowerLevelID}->{$nodeKey};
            } else {
                push @res, undef;
            }
        }
    }
    
    return @res;
}

=begin nd
Function: getChildren

Returns a <COMMON::Node> array, containing real children (max length = 4), an empty array if the node is a leaf.

Warning:
    Do not mistake with <getPossibleChildren>

Parameters (list):
    node - <COMMON::Node> - Node whose we want to know children.
=cut
sub getChildren {
    my $this = shift;
    my $node = shift;
    
    my @res;
    if ($node->getLevel eq $this->{bottomID}) {
        return @res;
    }
    
    my $lowerLevelID = $this->{pyramid}->getTileMatrixSet->getBelowLevelID($node->getLevel);
    
    for (my $j=0; $j<=1; $j++){
        for (my $i=0; $i<=1; $i++){
            my $nodeKey = sprintf "%s_%s",$node->getCol*2+$i, $node->getRow*2+$j;
            if (exists $this->{nodes}->{$lowerLevelID}->{$nodeKey}) {
                push @res, $this->{nodes}->{$lowerLevelID}->{$nodeKey};
            }
        }
    }
    
    return @res;
}

=begin nd
Function: getNodesOfLevel

Returns a <COMMON::Node> array, contaning all nodes of the provided level.

Parameters (list):
    level - string - Level ID whose we want all nodes.
=cut
sub getNodesOfLevel {
    my $this = shift;
    my $level = shift;
    
    if (! defined $level) {
        ERROR("Undefined Level");
        return undef;
    }
    
    return values (%{$this->{nodes}->{$level}});
}

# Function: getNodesOfTopLevel
sub getNodesOfTopLevel {
    my $this = shift;
    return $this->getNodesOfLevel($this->{topID});
}

####################################################################################################
#                                Group: Export methods                                             #
####################################################################################################

=begin nd
Function: exportLevelsForScript

Define levels into bash varaiables

Example:
    (start code)
    # QTree levels
    TOP_LEVEL="0"
    CUT_LEVEL="10"
    BOTTOM_LEVEL="11"
    (end code)
=cut
sub exportLevelsForScript {
    my $this = shift ;

    my $code = sprintf ("\n# QTree levels\n");
    $code .= sprintf ("TOP_LEVEL=\"%s\"\n", $this->{topID});
    $code .= sprintf ("CUT_LEVEL=\"%s\"\n", $this->{cutLevelID});
    $code .= sprintf ("BOTTOM_LEVEL=\"%s\"\n", $this->{bottomID});

    return $code;
}

=begin nd
Function: exportForDebug

Returns all informations about the quad tree. Useful for debug.

Example:
    (start code)
    (end code)
=cut
sub exportForDebug {
    my $this = shift ;
    
    my $export = "";
    
    $export .= sprintf "\nObject COMMON::QTree :\n";
    $export .= sprintf "\t Levels ID:\n";
    $export .= sprintf "\t\t- bottom : %s\n",$this->{bottomID};
    $export .= sprintf "\t\t- cut : %s\n",$this->{cutLevelID};
    $export .= sprintf "\t\t- top : %s\n",$this->{topID};

    $export .= sprintf "\t Number of nodes per level :\n";
    foreach my $level ( keys %{$this->{nodes}} ) {
        $export .= sprintf "\t\tLevel %s : %s node(s)\n",$level,scalar (keys %{$this->{nodes}->{$level}});
    }
    
    $export .= sprintf "\t Bbox (SRS : %s) :\n",$this->{pyramid}->getTileMatrixSet->getSRS;
    $export .= sprintf "\t\t- xmin : %s\n",$this->{bbox}[0];
    $export .= sprintf "\t\t- ymin : %s\n",$this->{bbox}[1];
    $export .= sprintf "\t\t- xmax : %s\n",$this->{bbox}[2];
    $export .= sprintf "\t\t- ymax : %s\n",$this->{bbox}[3];
    
    return $export;
}

1;
__END__
