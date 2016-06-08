/*
 * Copyright © (2011-2013) Institut national de l'information
 *                    géographique et forestière
 *
 * Géoportail SAV <geop_services@geoportail.fr>
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

/**
* \file Rok4Api.cpp
* \brief Implementation de l'API de ROK4
*/

#include "Rok4Api.h"
#include "config.h"
#include <proj_api.h>
#include "ConfLoader.h"
#include "Message.h"
#include "Request.h"
#include "RawImage.h"
#include "TiffEncoder.h"
#include "TiffHeaderDataSource.h"
#include "Palette.h"
#include <cstdlib>
#include "PNGEncoder.h"
#include "Decoder.h"
#include "Pyramid.h"
#include "TileMatrixSet.h"
#include "TileMatrix.h"
#include "intl.h"
#include "Context.h"
#include <cfloat>
#include <libintl.h>
#include "ServerXML.h"
#include "ServicesXML.h"

static bool loggerInitialised = false;
//Keep the servicesConf for deletion
static ServicesConf* sc = NULL;
/**
* \brief Initialisation d'une reponse a partir d'une source
* \brief Les donnees source sont copiees dans la reponse
*/
HttpResponse* initResponseFromSource ( DataSource* source ) {
    HttpResponse* response=new HttpResponse;
    response->status=source->getHttpStatus();
    response->type=new char[source->getType().length() +1];
    strcpy ( response->type,source->getType().c_str() );
    response->encoding=new char[source->getEncoding().length() +1];
    strcpy(response->encoding, source->getEncoding().c_str() );
    size_t buffer_size;
    const uint8_t *buffer = source->getData ( buffer_size );
    // TODO : tester sans copie memoire (attention, la source devrait etre supprimee plus tard)
    response->content=new uint8_t[buffer_size];
    memcpy ( response->content, ( uint8_t* ) buffer,buffer_size );
    response->contentSize=buffer_size;
    return response;
}

/**
* \brief Initialisation du serveur ROK4
* \param serverConfigFile : nom du fichier de configuration des parametres techniques
* \return : pointeur sur le serveur ROK4, NULL en cas d'erreur (forcement fatale)
*/

Rok4Server* rok4InitServer ( const char* serverConfigFile ) {

    ContextBook *cephContextBook = NULL;
    ContextBook *swiftContextBook = NULL;
    std::string strServerConfigFile = serverConfigFile;

    ServerXML* serverXML = ConfLoader::getTechnicalParam(strServerConfigFile);
    if ( ! serverXML->isOk() ) {
        std::cerr<<_ ( "ERREUR FATALE : Impossible d'interpreter le fichier de configuration du serveur " ) <<strServerConfigFile<<std::endl;
        return NULL;
    }

    if ( ! loggerInitialised ) {
        Logger::setOutput ( serverXML->getLogOutput() );

        // Initialisation du logger
        Accumulator *acc=0;
        switch ( serverXML->getLogOutput() ) {
            case ROLLING_FILE :
                acc = new RollingFileAccumulator ( serverXML->getLogFilePrefix(), serverXML->getLogFilePeriod() );
                break;
            case STATIC_FILE :
                acc = new StaticFileAccumulator ( serverXML->getLogFilePrefix() );
                break;
            case STANDARD_OUTPUT_STREAM_FOR_ERRORS :
                acc = new StreamAccumulator();
                break;
        }

        // Attention : la fonction Logger::setAccumulator n'est pas threadsafe
        for ( int i=0; i <= serverXML->getLogLevel(); i++ ) {
            Logger::setAccumulator ( ( LogLevel ) i, acc );
        }

        std::ostream &log = LOGGER ( DEBUG );
        log.precision ( 8 );
        log.setf ( std::ios::fixed,std::ios::floatfield );

        std::cout<< _ ( "Envoi des messages dans la sortie du logger" ) << std::endl;
        LOGGER_INFO ( _ ( "*** DEBUT DU FONCTIONNEMENT DU LOGGER ***" ) );
        loggerInitialised=true;
    } else {
        LOGGER_INFO ( _ ( "*** NOUVEAU CLIENT DU LOGGER ***" ) );
    }

    // Construction des parametres de service
    ServicesXML* servicesXML = ConfLoader::buildServicesConf ( serverXML->getServicesConfigFile() );
    if ( ! servicesXML->isOk() ) {
        LOGGER_FATAL ( _ ( "Impossible d'interpreter le fichier de conf " ) << serverXML->getServicesConfigFile() );
        LOGGER_FATAL ( _ ( "Extinction du serveur ROK4" ) );
        sleep ( 1 );    // Pour laisser le temps au logger pour se vider
        return NULL;
    }

    // Chargement des TMS
    std::map<std::string,TileMatrixSet*> tmsList;
    if ( ! ConfLoader::buildTMSList ( serverXML, tmsList ) ) {
        LOGGER_FATAL ( _ ( "Impossible de charger la conf des TileMatrix" ) );
        LOGGER_FATAL ( _ ( "Extinction du serveur ROK4" ) );
        sleep ( 1 );    // Pour laisser le temps au logger pour se vider
        return NULL;
    }

    //Chargement des styles
    std::map<std::string, Style*> styleList;
    if ( ! ConfLoader::buildStylesList ( serverXML, servicesXML, styleList ) ) {
        LOGGER_FATAL ( _ ( "Impossible de charger la conf des Styles" ) );
        LOGGER_FATAL ( _ ( "Extinction du serveur ROK4" ) );
        sleep ( 1 );    // Pour laisser le temps au logger pour se vider
        return NULL;
    }

    // Chargement des layers
    std::map<std::string, Layer*> layerList;
    if ( !ConfLoader::buildLayersList ( serverXML, servicesXML, tmsList, styleList, layerList) ) {
        LOGGER_FATAL ( _ ( "Impossible de charger la conf des Layers/pyramides" ) );
        LOGGER_FATAL ( _ ( "Extinction du serveur ROK4" ) );
        sleep ( 1 );    // Pour laisser le temps au logger pour se vider
        return NULL;
    }

    // Instanciation du serveur
    Logger::stopLogger();
    return new Rok4Server ( serverXML, servicesXML, layerList, tmsList, styleList );
}

/**
* \brief \~french Initialisation d'une requete \~english Initialize a request \~
* \param[in] queryString
* \param[in] hostName
* \param[in] scriptName
* \return Requete (memebres alloues ici, doivent etre desalloues ensuite)
*
* Requete HTTP, basee sur la terminologie des variables d'environnement Apache et completee par le type d'operation (au sens WMS/WMTS) de la requete
* Exemple :
* http://localhost/target/bin/rok4?SERVICE=WMTS&REQUEST=GetTile&tileCol=6424&tileRow=50233&tileMatrix=19&LAYER=ORTHO_RAW_IGNF_LAMB93&STYLES=&FORMAT=image/tiff&DPI=96&TRANSPARENT=TRUE&TILEMATRIXSET=LAMB93_10cm&VERSION=1.0.0
* queryString="SERVICE=WMTS&REQUEST=GetTile&tileCol=6424&tileRow=50233&tileMatrix=19&LAYER=ORTHO_RAW_IGNF_LAMB93&STYLES=&FORMAT=image/tiff&DPI=96&TRANSPARENT=TRUE&TILEMATRIXSET=LAMB93_10cm&VERSION=1.0.0"
* \arg \b hostName = "localhost"
* \arg \b scriptName = "/target/bin/rok4"
* \arg \b service = "wmts" \~french (en minuscules) \~english (lowercase)
* \arg \b operationType =  "gettile" \~french (en minuscules) \~english (lowercase)
*/

HttpRequest* rok4InitRequest ( const char* queryString, const char* hostName, const char* scriptName, const char* https , Rok4Server* server) {
    std::string strQuery=queryString;
    HttpRequest* request=new HttpRequest;
    request->queryString=new char[strQuery.length() +1];
    strcpy ( request->queryString,strQuery.c_str() );
    request->hostName=new char[strlen ( hostName ) +1];
    strcpy ( request->hostName,hostName );
    request->scriptName=new char[strlen ( scriptName ) +1];
    strcpy ( request->scriptName,scriptName );
    Request* rok4Request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );
    request->service=new char[rok4Request->service.length() +1];
    strcpy ( request->service,rok4Request->service.c_str() );
    request->operationType=new char[rok4Request->request.length() +1];
    strcpy ( request->operationType,rok4Request->request.c_str() );
    request->error_response = 0;
    
    std::map<std::string, std::string>::iterator it = rok4Request->params.find ( "nodataashttpstatus" );
    if ( it == rok4Request->params.end() ) {
        request->noDataAsHttpStatus = 0;
    } else {
        request->noDataAsHttpStatus = 1;
    }
    
    //Vérification des erreurs et ecriture dans error_response
    if ( rok4Request->service == "wmts" ) {
        if ( rok4Request->request == "") {
            request->error_response = initResponseFromSource( new SERDataSource ( new ServiceException ( "",OWS_MISSING_PARAMETER_VALUE,_ ( "Le parametre REQUEST n'est pas renseigné." ),"wmts" ) ));
        } else if ( rok4Request->request == "getcapabilities" || rok4Request->request == "gettile" || rok4Request->request == "getfeatureinfo") {
            //No error for the moment
        } else if ( rok4Request->request == "getversion" ) {
            request->error_response = initResponseFromSource( new SERDataSource ( new ServiceException ( "",OWS_OPERATION_NOT_SUPORTED, ( "L'operation " ) +rok4Request->request+_ ( " n'est pas prise en charge par ce serveur." ) + ROK4_INFO,"wmts" ) ));
        } else {
            request->error_response = initResponseFromSource( new SERDataSource ( new ServiceException ( "",OWS_OPERATION_NOT_SUPORTED,_ ( "L'operation " ) +rok4Request->request+_ ( " n'est pas prise en charge par ce serveur." ),"wmts" ) ));
        }
    } else if (rok4Request->service == ""){
        request->error_response = initResponseFromSource( new SERDataSource ( new ServiceException ( "",OWS_MISSING_PARAMETER_VALUE,_ ( "Le parametre SERVICE n'est pas renseigné." ),"wmts" ) ));
    } else {
        request->error_response = initResponseFromSource( new SERDataSource ( new ServiceException ( "",OWS_INVALID_PARAMETER_VALUE,_ ( "Le service " ) +rok4Request->service+_ ( " est inconnu pour ce serveur." ),"wmts" ) ));
    }
        
        

    delete rok4Request;
    return request;
}

/**
* \brief Implementation de l'operation GetCapabilities pour le WMTS
* \param[in] hostName
* \param[in] scriptName
* \param[in] server : serveur
* \return Reponse (allouee ici, doit etre desallouee ensuite)
*/

HttpResponse* rok4GetWMTSCapabilities ( const char* queryString, const char* hostName, const char* scriptName,const char* https ,Rok4Server* server ) {
    std::string strQuery=queryString;
    Request* request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );
    DataStream* stream=server->WMTSGetCapabilities ( request );
    DataSource* source= new BufferedDataSource ( *stream );
    HttpResponse* response=initResponseFromSource ( /*new BufferedDataSource(*stream)*/source );
    delete request;
    delete stream;
    delete source;
    return response;
}

/**
* \brief Implementation de l'operation GetFeatureInfo pour le WMTS
* \param[in] hostName
* \param[in] scriptName
* \param[in] server : serveur
* \return Reponse (allouee ici, doit etre desallouee ensuite)
*/

HttpResponse* rok4GetWMTSGetFeatureInfo ( const char* queryString, const char* hostName, const char* scriptName,const char* https ,Rok4Server* server ) {
    std::string strQuery=queryString;
    Request* request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );

    DataStream* stream=server->WMTSGetFeatureInfo ( request );
    DataSource* source= new BufferedDataSource ( *stream );
    HttpResponse* response=initResponseFromSource ( source );

    delete request;
    delete source;
    return response;
}

/**
* \brief Implementation de l'operation GetTile
* \param[in] queryString
* \param[in] hostName
* \param[in] scriptName
* \param[in] server : serveur
* \return Reponse (allouee ici, doit etre desallouee ensuite)
*/

HttpResponse* rok4GetTile ( const char* queryString, const char* hostName, const char* scriptName,const char* https, Rok4Server* server ) {
    std::string strQuery=queryString;
    Request* request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );
    DataSource* source=server->getTile ( request );
    HttpResponse* response=initResponseFromSource ( source );
    delete request;
    delete source;
    return response;
}

/**
* \brief Implementation de l'operation ExistObjectCeph
* \brief Cela permet de tester l'existance d'un objet sur Ceph
* \param[in] server
* \param[in] nom de l'objet
* \param[in] pool contenant l'objet
* \return int 1 si l'objet existe, 0 sinon
*/


int rok4ExistObjectCeph(Rok4Server* server, const char* name, const char* pool) {
    LOGGER_INFO("Rok4Api : Test existence sur Ceph" << pool << " / " << name);

    ContextBook * cb = server->getCephBook();
    if (cb == NULL) {
        LOGGER_ERROR("Pas de ceph book");
        return false;
    }

    Context * ctx = cb->getContext(pool);
    if (ctx == NULL) {
        LOGGER_ERROR("Pas de context pour ce pool");
        return false;
    }

    uint8_t data[1];
    int readSize = ctx->read(data, 0, 1, (std::string)name);

    return (readSize == 1);

}

/**
* \brief Implementation de l'operation ReadObjectCeph
* \brief Cela permet de transmettre une donnée issue de ceph
* \param[in] server
* \param[in] nom de l'objet
* \param[in] pool contenant l'objet
* \param[in] offset
* \param[in] size
* \param[in/out] data
* \return int taille lue ou erreur
*/
int rok4ReadObjectCeph(Rok4Server* server, const char* name, const char* pool, int offset, int size, char* data) {

     int err = -1;

     Context * ctx = server->getCephBook()->getContext(pool);
     if (ctx == NULL) {
         return err;
     }

     err = ctx->read((uint8_t*)data, offset, size, (std::string)name);

     return err;

}

/**
* \brief Implementation de l'operation ReadObjectSwift
* \brief Cela permet de transmettre une donnée issue de swift
* \param[in] server
* \param[in] nom de l'objet
* \param[in] pool contenant l'objet
* \param[in] offset
* \param[in] size
* \param[in/out] data
* \return int taille lue ou erreur
*/


int rok4ReadObjectSwift(Rok4Server* server, const char* name, const char* pool, int offset, int size, char* data) {

    int err = -1;

    Context * ctx = server->getSwiftBook()->getContext(pool);
    if (ctx == NULL) {
        return err;
    }

    err = ctx->read((uint8_t*)data, offset, size, (std::string)name);

    return err;

}

/**
* \brief Implementation de l'operation GetTile modifiee
* \brief La tuile n'est pas lue, les elements recuperes sont les references de la tuile : le fichier dans lequel elle est stockee et les positions d'enregistrement (sur 4 octets) dans ce fichier de l'index du premier octet de la tuile et de sa taille
* \param[in] queryString
* \param[in] hostName
* \param[in] scriptName
* \param[in] server : serveur
* \param[out] tileRef : reference de la tuile (la variable filename est allouee ici et doit etre desallouee ensuite)
* \param[out] palette : palette à ajouter, NULL sinon.
* \return Reponse en cas d'exception, NULL sinon
*/

HttpResponse* rok4GetTileReferences ( const char* queryString, const char* hostName, const char* scriptName, const char* https, Rok4Server* server, TileRef* tileRef, TilePalette* palette ) {
    // Initialisation
    std::string strQuery=queryString;

    Request* request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );
    Layer* layer;
    std::string tmId,mimeType,format,encoding,imageFilePath, wmtst;
    int x,y;
    Style* style =0;
    // Analyse de la requete
    bool errorNoData;
    DataSource* errorResp = request->getTileParam ( server->getServicesConf(), server->getTmsList(), server->getLayerList(), layer, tmId, x, y, mimeType, style, errorNoData );
    // Exception
    if ( errorResp ) {
        LOGGER_ERROR ( _ ( "Probleme dans les parametres de la requete getTile" ) );
        HttpResponse* error=initResponseFromSource ( errorResp );
        delete request;
        delete errorResp;
        return error;
    }

    // References de la tuile
    std::map<std::string, Level*>::iterator itLevel=layer->getDataPyramid()->getLevels().find ( tmId );
    if ( itLevel==layer->getDataPyramid()->getLevels().end() ) {
        //Should not occurs.
        delete request;
        return rok4GetNoDataFoundException();
    }
    Level* level=layer->getDataPyramid()->getLevels().find ( tmId )->second;

    if (level->getTilesPerHeight() == 0 && level->getTilesPerWidth() == 0) {
        //on doit lire une tuile et non une dalle
        imageFilePath=level->getPath ( x, y,1, 1);
        tileRef->posoff = 0;
        tileRef->possize = 0;

        std::string strType = "TILE";
        tileRef->storeType=new char[strType.length() +1];
        strcpy ( tileRef->storeType,strType.c_str() );

    } else {
        //on lit une dalle
        int n= ( y%level->getTilesPerHeight() ) *level->getTilesPerWidth() + ( x%level->getTilesPerWidth() );
        tileRef->posoff=2048+4*n;
        tileRef->possize=2048+4*n +level->getTilesPerWidth() *level->getTilesPerHeight() *4;
        imageFilePath=level->getPath ( x, y,level->getTilesPerWidth(), level->getTilesPerHeight());

        std::string strType = "SLAB";
        tileRef->storeType=new char[strType.length() +1];
        strcpy ( tileRef->storeType,strType.c_str() );

    }
    tileRef->name=new char[imageFilePath.length() +1];
    strcpy ( tileRef->name,imageFilePath.c_str() );

    tileRef->maxsize = level->getMaxTileSize();

    std::string ctxType = level->getContext()->getTypeStr();
    tileRef->contextType=new char[ctxType.length() +1];
    strcpy ( tileRef->contextType,ctxType.c_str() );

    std::string container = level->getContext()->getBucket();
    tileRef->pool=new char[container.length() +1];
    strcpy ( tileRef->pool,container.c_str() );

    tileRef->type=new char[mimeType.length() +1];
    strcpy ( tileRef->type,mimeType.c_str() );

    tileRef->width=level->getTm().getTileW();
    tileRef->height=level->getTm().getTileH();
    tileRef->channels=level->getChannels();

    format = Rok4Format::toString ( layer->getDataPyramid()->getFormat() );
    tileRef->format= new char[format.length() +1];
    strcpy ( tileRef->format, format.c_str() );

    //Palette uniquement PNG pour le moment
    if ( mimeType == "image/png" ) {
        palette->size = style->getPalette()->getPalettePNGSize();
        palette->data = style->getPalette()->getPalettePNG();
    } else {
        palette->size = 0;
        palette->data = NULL;
    }
    
    encoding = Rok4Format::toEncoding( level->getFormat() );
    tileRef->encoding = new char[encoding.length() +1];
    strcpy( tileRef->encoding, encoding.c_str() );

    if (layer->getDataPyramid()->getOnFly()) {
        wmtst = "ONFLY";
        tileRef->wmtsType = new char[wmtst.length() +1];
        strcpy( tileRef->wmtsType, wmtst.c_str() );
    } else {
        if (layer->getDataPyramid()->getOnDemand()) {
            wmtst = "ONDEMAND";
            tileRef->wmtsType = new char[wmtst.length() +1];
            strcpy( tileRef->wmtsType, wmtst.c_str() );
        } else {
            wmtst = "NORMAL";
            tileRef->wmtsType = new char[wmtst.length() +1];
            strcpy( tileRef->wmtsType, wmtst.c_str() );
        }
    }

    delete request;
    return 0;
}

/**
* \brief Implementation de l'operation GetNoDataTile
* \brief La tuile n'est pas lue, les elements recuperes sont les references de la tuile : le fichier dans lequel elle est stockee et les positions d'enregistrement (sur 4 octets) dans ce fichier de l'index du premier octet de la tuile et de sa taille
* \param[in] queryString
* \param[in] hostName
* \param[in] scriptName
* \param[in] server : serveur
* \param[out] tileRef : reference de la tuile (la variable filename est allouee ici et doit etre desallouee ensuite)
* \param[out] palette : palette à ajouter, NULL sinon.
* \return Reponse en cas d'exception, NULL sinon
*/
HttpResponse* rok4GetNoDataTileReferences ( const char* queryString, const char* hostName, const char* scriptName, const char* https, Rok4Server* server, TileRef* tileRef, TilePalette* palette ) {
// Initialisation
    std::string strQuery=queryString;

    Request* request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );
    Layer* layer;
    std::string tmId,format,encoding;
    int x,y;
    Style* style =0;
    bool errorNoData;
    // Analyse de la requete
    DataSource* errorResp = request->getTileParam ( server->getServicesConf(), server->getTmsList(), server->getLayerList(), layer, tmId, x, y, format, style, errorNoData );
    // Exception
    if ( errorResp ) {
        LOGGER_ERROR ( _ ( "Probleme dans les parametres de la requete getTile" ) );
        HttpResponse* error=initResponseFromSource ( errorResp );
        delete errorResp;
        return error;
    }

    // References de la tuile
    Level* level;
    std::map<std::string, Level*>::iterator itLevel=layer->getDataPyramid()->getLevels().find ( tmId );
    if ( itLevel==layer->getDataPyramid()->getLevels().end() ) {
        //Pick the nearest available level for NoData
        std::map<std::string, TileMatrix>::iterator itTM;
        double askedRes;

        itTM = layer->getDataPyramid()->getTms().getTmList()->find ( tmId );
        if ( itTM==layer->getDataPyramid()->getTms().getTmList()->end() ) {
            //return the lowest Level available
            level = layer->getDataPyramid()->getLowestLevel();
        }
        askedRes = itTM->second.getRes();
        level = ( askedRes > layer->getDataPyramid()->getLowestLevel()->getRes() ? layer->getDataPyramid()->getHighestLevel() : layer->getDataPyramid()->getLowestLevel() );
    } else {
        level = layer->getDataPyramid()->getLevels().find ( tmId )->second;
    }

    tileRef->posoff=2048;
    tileRef->possize=2048+4;
    tileRef->maxsize = level->getMaxTileSize();

    std::string imageFilePath=level->getNoDataFilePath();
    tileRef->name=new char[imageFilePath.length() +1];
    strcpy ( tileRef->name,imageFilePath.c_str() );

    std::string ctxType = level->getContext()->getTypeStr();;
    tileRef->contextType=new char[ctxType.length() +1];
    strcpy ( tileRef->contextType,ctxType.c_str() );

    std::string container = level->getContext()->getBucket();;
    tileRef->pool=new char[container.length() +1];
    strcpy ( tileRef->pool,container.c_str() );

    tileRef->type=new char[format.length() +1];
    strcpy ( tileRef->type,format.c_str() );
    
    encoding = Rok4Format::toEncoding( level->getFormat() );
    tileRef->encoding = new char[encoding.length() +1];
    strcpy( tileRef->encoding, encoding.c_str() );

    tileRef->width=level->getTm().getTileW();
    tileRef->height=level->getTm().getTileH();
    tileRef->channels=level->getChannels();
    
    format = Rok4Format::toString ( layer->getDataPyramid()->getFormat() );
    tileRef->format= new char[format.length() +1];
    strcpy ( tileRef->format, format.c_str() );

//Palette uniquement PNG pour le moment
    if ( format == "image/png" ) {
        palette->size = style->getPalette()->getPalettePNGSize();
        palette->data = style->getPalette()->getPalettePNG();
    } else {
        palette->size = 0;
        palette->data = NULL;
    }

    delete request;
    return 0;
}


/**
* \brief Construction d'un en-tete TIFF
* \deprecated
*/

TiffHeader* rok4GetTiffHeader ( int width, int height, int channels ) {
    TiffHeader* header = new TiffHeader;
    RawImage* rawImage=new RawImage ( width,height,channels,0 );
    DataStream* tiffStream = TiffEncoder::getTiffEncoder ( rawImage, Rok4Format::TIFF_RAW_INT8 );
    tiffStream->read ( header->data,128 );
    delete tiffStream;
    return header;
}

/**
* \brief Construction d'un en-tete TIFF
*/

TiffHeader* rok4GetTiffHeaderFormat ( int width, int height, int channels, char* format, uint32_t possize ) {
    TiffHeader* header = new TiffHeader;
    size_t tiffHeaderSize;
    const uint8_t* tiffHeader;
    TiffHeaderDataSource* fullTiffDS = new TiffHeaderDataSource ( 0,Rok4Format::fromString ( format ),channels,width,height,possize );
    tiffHeader = fullTiffDS->getData ( tiffHeaderSize );
    header->size = tiffHeaderSize;
    header->data = ( uint8_t* ) malloc ( tiffHeaderSize+1 );
    memcpy ( header->data,tiffHeader,tiffHeaderSize );
    delete fullTiffDS;
    return header;
}

/**
* \brief Construction d'un en-tete PNG avec Palette
*/

PngPaletteHeader* rok4GetPngPaletteHeader ( int width, int height, TilePalette* palette ) {
    PngPaletteHeader* header = new PngPaletteHeader;
    //RawImage* rawImage=new RawImage(width,height,1,0);
    Palette rok4Palette = Palette ( palette->size,palette->data );
    PNGEncoder pngStream ( new ImageDecoder ( 0,width,height,1 ),&rok4Palette );
    header->size = 33 + palette->size;
    header->data = ( uint8_t* ) malloc ( header->size+1 );
    pngStream.read ( header->data,header->size );
    return header;
}


/**
* \brief Renvoi d'une exception pour une operation non prise en charge
*/

HttpResponse* rok4GetOperationNotSupportedException ( const char* queryString, const char* hostName, const char* scriptName,const char* https, Rok4Server* server ) {

    std::string strQuery=queryString;
    Request* request=new Request ( ( char* ) strQuery.c_str(), ( char* ) hostName, ( char* ) scriptName, ( char* ) https );
    DataSource* source=new SERDataSource ( new ServiceException ( "",OWS_OPERATION_NOT_SUPORTED,_ ( "L'operation " ) +request->request+_ ( " n'est pas prise en charge par ce serveur." ),"wmts" ) );
    HttpResponse* response=initResponseFromSource ( source );
    delete request;
    delete source;
    return response;
}

/**
 * \brief Renvoi l'exception No data found
 */
HttpResponse* rok4GetNoDataFoundException () {

    DataSource* source=new SERDataSource ( new ServiceException ( "", HTTP_NOT_FOUND, _ ( "No data found" ), "wmts" ) );
    HttpResponse* response=initResponseFromSource ( source );
    delete source;
    return response;
}

/**
* \brief Suppression d'une requete
*/

void rok4DeleteRequest ( HttpRequest* request ) {
    delete[] request->queryString;
    delete[] request->hostName;
    delete[] request->scriptName;
    delete[] request->service;
    delete[] request->operationType;
    if (request->error_response != 0){
        rok4DeleteResponse(request->error_response);
        delete request->error_response;
    }
    delete request;
}

/**
* \brief Suppression d'une reponse
*/

void rok4DeleteResponse ( HttpResponse* response ) {
    delete[] response->type;
    delete[] response->encoding;
    delete[] response->content;
    delete response;
}

/**
* \brief Suppression des champs d'une reference de tuile
* La reference n est pas supprimee
*/

void rok4FlushTileRef ( TileRef* tileRef ) {
    delete[] tileRef->name;
    delete[] tileRef->pool;
    delete[] tileRef->contextType;
    delete[] tileRef->storeType;
    delete[] tileRef->type;
    delete[] tileRef->encoding;
    delete[] tileRef->format;
    delete[] tileRef->wmtsType;
}

/**
* \brief Suppression des champs d'une reference de ceph
* La reference n est pas supprimee
*/

void rok4FlushCephRef ( CephRef* cephRef ) {
    delete[] cephRef->name;
    delete[] cephRef->user;
    delete[] cephRef->conf;
}

/**
* \brief Suppression d'un en-tete TIFF
*/

void rok4DeleteTiffHeader ( TiffHeader* header ) {
    delete header;
}

/**
* \brief Suppression d'un en-tete Png avec Palette
*/

void rok4DeletePngPaletteHeader ( PngPaletteHeader* header ) {
    //free (header->data);
    delete header;
}

/**
* \brief Suppression d'une Palette
*/

void rok4DeleteTilePalette ( TilePalette* palette ) {
    delete palette;
}


/**
* \brief Extinction du serveur
*/

void rok4KillServer ( Rok4Server* server ) {
    LOGGER_INFO ( _ ( "Extinction du serveur ROK4" ) );

    std::map<std::string,TileMatrixSet*>::iterator iTms;
    for ( iTms = server->getTmsList().begin(); iTms != server->getTmsList().end(); iTms++ )
        delete ( *iTms ).second;

    std::map<std::string, Style*>::iterator iStyle;
    for ( iStyle = server->getStyleList().begin(); iStyle != server->getStyleList().end(); iStyle++ )
        delete ( *iStyle ).second;

    std::map<std::string, Layer*>::iterator iLayer;
    for ( iLayer = server->getLayerList().begin(); iLayer != server->getLayerList().end(); iLayer++ )
        delete ( *iLayer ).second;

    //Clear proj4 cache
    pj_clear_initcache();

    delete sc;
    delete server;
    sc = NULL;
}

/**
* \brief Connexion aux contexts contenus dans les contextBook du serveur
*/

int rok4ConnectObjectContext(Rok4Server* server) {

    int error = 1;

    ContextBook *book = server->getCephBook();

    if (book) {
        if (!book->connectAllContext()) {
            return error;
        }
    }

    book = server->getSwiftBook();

    if (book) {
        if (!book->connectAllContext()) {
            return error;
        }
    }

    return 0;

}

/**
* \brief Deconnexion aux contexts contenus dans les contextBook du serveur
*/

void rok4DisconnectObjectContext(Rok4Server* server) {

    ContextBook *book = server->getCephBook();

    if (book) {
        book->disconnectAllContext();
    }

    book = server->getSwiftBook();

    if (book) {
        book->disconnectAllContext();
    }

}

/**
 * \brief Extinction du Logger
 */
void rok4KillLogger() {
    loggerInitialised = false;
    Accumulator* acc = NULL;
    for ( int i=0; i<= nbLogLevel ; i++ )
        if ( Logger::getAccumulator ( ( LogLevel ) i ) ) {
            acc = Logger::getAccumulator ( ( LogLevel ) i );
            break;
        }
    Logger::stopLogger();
    if ( acc ) {
        acc->stop();
        acc->destroy();
        delete acc;
    }

}

/**
 * \brief Fermeture des descripteurs de fichiers
 */
void rok4ReloadLogger() {
    Accumulator* acc = NULL;
    for ( int i=0; i<= nbLogLevel ; i++ )
        if ( Logger::getAccumulator ( ( LogLevel ) i ) ) {
            acc = Logger::getAccumulator ( ( LogLevel ) i );
            break;
        }
    if ( acc ) {
        acc->close();
    }
}


