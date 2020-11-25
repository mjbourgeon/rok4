/*
 * Copyright © (2011-2013) Institut national de l'information
 *                    géographique et forestière
 *
 * Géoportail SAV <contact.geoservices@ign.fr>
 *
 * This software is a computer program whose purpose is to publish geographic
 * data using OGC WMS and WMTS protocol.
 *
 * This software is governed by the CeCILL-C license under French law and
 * abiding by the rules of distribution of free software.  You can  use,
 * modify and/ or redistribute the software under the terms of the CeCILL-C
 * license as circulated by CEA, CNRS and INRIA at the following URL
 * "http://www.cecill.info".
 *
 * As a counterpart to the access to the source code and  rights to copy,
 * modify and redistribute granted by the license, users are provided only
 * with a limited warranty  and the software's author,  the holder of the
 * economic rights,  and the successive licensors  have only  limited
 * liability.
 *
 * In this respect, the user's attention is drawn to the risks associated
 * with loading,  using,  modifying and/or developing or reproducing the
 * software by the user in light of its specific status of free software,
 * that may mean  that it is complicated to manipulate,  and  that  also
 * therefore means  that it is reserved for developers  and  experienced
 * professionals having in-depth computer knowledge. Users are therefore
 * encouraged to load and test the software's suitability as regards their
 * requirements in conditions enabling the security of their systems and/or
 * data to be ensured and,  more generally, to use and operate it in the
 * same conditions as regards security.
 *
 * The fact that you are presently reading this means that you have had
 *
 * knowledge of the CeCILL-C license and that you accept its terms.
 */

class LevelXML;

#ifndef LEVELXML_H
#define LEVELXML_H

#include <vector>
#include <string>

#include "Level.h"
#include "TileMatrixSet.h"
#include "DocumentXML.h"
#include "ServerXML.h"
#include "Context.h"
#include "Table.h"
#include "Attribute.h"

#include "config.h"
#include "intl.h"

class LevelXML : public DocumentXML
{
    friend class Level;

    public:
        LevelXML(TiXmlElement* levelElement, std::string path, ServerXML* serverXML, ServicesXML* servicesXML, PyramidXML* pyr, bool times);
        ~LevelXML();

        std::string getId();

        bool isOnDemand();
        bool isOnFly();

        bool isOk();

    protected:

        //----VARIABLE
        TileMatrix* tm;
        std::string id;

        int32_t minTileRow;    
        int32_t maxTileRow;    
        int32_t minTileCol;    
        int32_t maxTileCol;  

        int tilesPerWidth;
        int tilesPerHeight;

        Context *context;


        std::string baseDir;
        int pathDepth;

        std::string prefix;

        /******************* PYRAMIDE VECTEUR *********************/
        std::vector<Table> tables;
        
        /******************* PYRAMIDE RASTER (OD) *********************/
        std::vector<Source*> sSources;
        // Sans stockage
        bool onDemand;
        // Avec stockage
        bool onFly;

    private:

        bool ok;
        int calculateTileLimits(PyramidXML* pyrxml);
};

#endif // LEVELXML_H

