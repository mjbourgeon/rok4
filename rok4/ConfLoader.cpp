#include <dirent.h>
#include "ConfLoader.h"
#include "Pyramid.h"
#include "tinyxml.h"
#include "tinystr.h"
#include "config.h"

TileMatrixSet* buildTileMatrixSet(std::string fileName){
	LOGGER_INFO("	Ajout du TMS " << fileName);
	std::string id;
	std::string title="";
	std::string abstract="";
	std::vector<std::string> keyWords;
	std::map<std::string, TileMatrix> listTM;

	TiXmlDocument doc(fileName.c_str());
	if (!doc.LoadFile()){
		LOGGER_ERROR("		Ne peut pas charger le fichier " << fileName);
		return NULL;
	}

	TiXmlHandle hDoc(&doc);
	TiXmlElement* pElem;
	TiXmlHandle hRoot(0);

	pElem=hDoc.FirstChildElement().Element(); //recuperation de la racine.
	if (!pElem){
		LOGGER_ERROR(fileName << "		Impossible de recuperer la racine.");
		return NULL;
	}
	if (strcmp(pElem->Value(),"tileMatrixSet")){
		LOGGER_ERROR(fileName << "		La racine n'est pas un tileMatrixSet.");
		return NULL;
	}
	hRoot=TiXmlHandle(pElem);

	unsigned int idBegin=fileName.rfind("/");
	if (idBegin == std::string::npos){
		idBegin=0;
	}
	unsigned int idEnd=fileName.rfind(".tms");
	if (idEnd == std::string::npos){
		idEnd=fileName.rfind(".TMS");
		if (idEnd == std::string::npos){
			idEnd=fileName.size();
		}
	}
	id=fileName.substr(idBegin+1, idEnd-idBegin-1);

	pElem=hRoot.FirstChild("crs").Element();
	if (!pElem){
		LOGGER_ERROR("TileMaxtrixSet " << id <<" pas de crs!!");
		return NULL;
	}
	CRS crs(pElem->GetText());

	pElem=hRoot.FirstChild("abstract").Element();
	if (pElem) abstract = pElem->GetText();

	pElem=hRoot.FirstChild("title").Element();
	if (pElem) title = pElem->GetText();


	for (pElem=hRoot.FirstChild("keywordList").FirstChild("keyword").Element(); pElem; pElem=pElem->NextSiblingElement("keyword")){
		std::string keyword(pElem->GetText());
		keyWords.push_back(keyword);
	}

	for( pElem=hRoot.FirstChild( "tileMatrix" ).Element(); pElem; pElem=pElem->NextSiblingElement( "tileMatrix")){
		std::string tmId;
		double res;
		double x0;
		double y0;
		int tileW;
		int tileH;
		long int matrixW;
		long int matrixH;

		TiXmlHandle hTM(pElem);
		TiXmlElement* pElemTM = hTM.FirstChild("id").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMatrix sans id!!"); return NULL; }
		tmId=pElemTM->GetText();

		pElemTM = hTM.FirstChild("resolution").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans resolution!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%lf",&res)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMaxtrix " << tmId <<": La resolution est inexploitable.");
			return NULL;
		}

		pElemTM = hTM.FirstChild("topLeftCornerX").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans topLeftCornerX!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%lf",&x0)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMaxtrix " << tmId <<": Le topLeftCornerX est inexploitable.");
			return NULL;
		}

		pElemTM = hTM.FirstChild("topLeftCornerY").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans topLeftCornerY!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%lf",&y0)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMaxtrix " << tmId <<": Le topLeftCornerY est inexploitable.");
			return NULL;
		}

		pElemTM = hTM.FirstChild("tileWidth").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans tileWidth!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%d",&tileW)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMaxtrix " << tmId <<": Le tileWidth est inexploitable.");
			return NULL;
		}

		pElemTM = hTM.FirstChild("tileHeight").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans tileHeight!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%d",&tileH)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMaxtrix " << tmId <<": Le tileHeight est inexploitable.");
			return NULL;
		}

		pElemTM = hTM.FirstChild("matrixWidth").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans MatrixWidth!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%ld",&matrixW)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", TileMaxtrix " << tmId <<": Le MatrixWidth est inexploitable.");
			return NULL;
		}

		pElemTM = hTM.FirstChild("matrixHeight").Element();
		if (!pElemTM){LOGGER_ERROR("TileMaxtrixSet " << id <<" tileMatrix " << tmId <<" sans matrixHeight!!"); return NULL; }
		if (!sscanf(pElemTM->GetText(),"%ld",&matrixH)){
			LOGGER_ERROR("TileMaxtrixSet " << id <<", tileMaxtrix " << tmId <<": Le matrixHeight est inexploitable.");
			return NULL;
		}

		TileMatrix tm(tmId, res, x0, y0, tileW, tileH, matrixW, matrixH);
		listTM.insert(std::pair<std::string, TileMatrix> (tmId, tm));

	}// boucle sur le TileMatrix

	if (listTM.size()==0){
		LOGGER_ERROR("Aucun tileMatrix trouvé dans le tileMatrixSet" << id <<" : il est invalide!!");
		return NULL;
	}
	TileMatrixSet * tms = new TileMatrixSet(id,title,abstract,keyWords,crs,listTM);
	return tms;

}//buildTileMatrixSet(std::string)

Pyramid* buildPyramid(std::string fileName, std::map<std::string, TileMatrixSet*> &tmsList){
	LOGGER_INFO("		Ajout de la pyramide : " << fileName);
	TileMatrixSet *tms;
	std::string format;	
	int channels;
	std::map<std::string, Level *> levels;

	TiXmlDocument doc(fileName.c_str());
	if (!doc.LoadFile()){
		LOGGER_ERROR("Ne peut pas charger le fichier " << fileName);
		return NULL;
	}

	TiXmlHandle hDoc(&doc);
	TiXmlElement* pElem;
	TiXmlHandle hRoot(0);

	pElem=hDoc.FirstChildElement().Element(); //recuperation de la racine.
	if (!pElem){
		LOGGER_ERROR(fileName << " impossible de recuperer la racine.");
		return NULL;
	}
	if (strcmp(pElem->Value(),"Pyramid")){
		LOGGER_ERROR(fileName << " La racine n'est pas une Pyramid.");
		return NULL;
	}
	hRoot=TiXmlHandle(pElem);

	pElem=hRoot.FirstChild("tileMatrixSet").Element();
	if (!pElem){
		LOGGER_ERROR("La pyramide ["<< fileName <<"] n'a pas de TMS. C'est un problème.");
		return NULL;
	}
	std::string tmsName=pElem->GetText();
	std::map<std::string, TileMatrixSet *>::iterator it;
	it=tmsList.find(tmsName);
	if(it == tmsList.end()){
		LOGGER_ERROR("La Pyramide ["<< fileName <<"] reference un TMS ["<< tmsName <<"] qui n'existe pas.");
		return NULL;
	}
	tms=it->second;

	pElem=hRoot.FirstChild("format").Element();
        if (!pElem){
                LOGGER_ERROR("La pyramide ["<< fileName <<"] n'a pas de format.");
                return NULL;
        }
	format=pElem->GetText();
        if (format.compare("TIFF_INT8")!=0
         && format.compare("TIFF_JPG_INT8")!=0
         && format.compare("TIFF_PNG_INT8")!=0
         && format.compare("TIFF_LZW_INT8")!=0
         && format.compare("TIFF_FLOAT32")!=0){
                LOGGER_ERROR(fileName << "Le format ["<< format <<"] n'est pas gere.");
                return NULL;
        }
        format=pElem->GetText();

	pElem=hRoot.FirstChild("channels").Element();
        if (!pElem){
		LOGGER_ERROR("La pyramide ["<< fileName <<"] Pas de channels => channels = " << DEFAULT_CHANNELS);
                channels=DEFAULT_CHANNELS;
                return NULL;
        }else if (!sscanf(pElem->GetText(),"%d",&channels)){
                LOGGER_ERROR("La pyramide ["<< fileName <<"] : channels=[" << pElem->GetText() <<"] n'est pas un entier.");
                return NULL;
        }

	for( pElem=hRoot.FirstChild( "level" ).Element(); pElem; pElem=pElem->NextSiblingElement( "level")){
		TileMatrix *tm;
		std::string id;
		std::string baseDir;
		int32_t minTileRow=-1; // valeur conventionnelle pour indiquer que cette valeur n'est pas renseignée.
		int32_t maxTileRow=-1; // valeur conventionnelle pour indiquer que cette valeur n'est pas renseignée.
		int32_t minTileCol=-1; // valeur conventionnelle pour indiquer que cette valeur n'est pas renseignée.
		int32_t maxTileCol=-1; // valeur conventionnelle pour indiquer que cette valeur n'est pas renseignée.
		int tilesPerWidth;
		int tilesPerHeight;
		int pathDepth;

		TiXmlHandle hLvl(pElem);
		TiXmlElement* pElemLvl = hLvl.FirstChild("tileMatrix").Element();
		if (!pElemLvl){LOGGER_ERROR(fileName <<" level "<<id<<" sans tileMatrix!!"); return NULL; }
		std::string tmName(pElemLvl->GetText());
		id=tmName;
		std::map<std::string, TileMatrix>* tmList = tms->getTmList();
		std::map<std::string, TileMatrix>::iterator it = tmList->find(tmName);

		if(it == tmList->end()){
			LOGGER_ERROR(fileName <<" Le level "<< id <<" ref. Le TM [" << tmName << "] qui n'appartient pas au TMS [" << tmsName << "]");
			return NULL;
		}
		tm = &(it->second);

		pElemLvl = hLvl.FirstChild("baseDir").Element();
		if (!pElemLvl){LOGGER_ERROR(fileName <<" Level "<< id <<" sans baseDir!!"); return NULL; }
		baseDir=pElemLvl->GetText();

		pElemLvl = hLvl.FirstChild("tilesPerWidth").Element();
		if (!pElemLvl){
			LOGGER_ERROR(fileName <<" Level "<< id << ": Pas de tilesPerWidth !!");
			return NULL;
		}
		if (!sscanf(pElemLvl->GetText(),"%d",&tilesPerWidth)){
			LOGGER_ERROR(fileName <<" Level "<< id <<": tilesPerWidth=[" << pElemLvl->GetText() <<"] n'est pas un entier.");
			return NULL;
		}

		pElemLvl = hLvl.FirstChild("tilesPerHeight").Element();
		if (!pElemLvl){
			LOGGER_ERROR(fileName <<" Level "<< id << ": Pas de tilesPerHeight !!");
			return NULL;
		}
		if (!sscanf(pElemLvl->GetText(),"%d",&tilesPerHeight)){
			LOGGER_ERROR(fileName <<" Level "<< id <<": tilesPerHeight=[" << pElemLvl->GetText() <<"] n'est pas un entier.");
			return NULL;
		}

		pElemLvl = hLvl.FirstChild("pathDepth").Element();
		if (!pElemLvl){
			LOGGER_ERROR(fileName <<" Level "<< id << ": Pas de pathDepth !!");
			return NULL;
		}
		if (!sscanf(pElemLvl->GetText(),"%d",&pathDepth)){
			LOGGER_ERROR(fileName <<" Level "<< id <<": pathDepth=[" << pElemLvl->GetText() <<"] n'est pas un entier.");
			return NULL;
		}

		TiXmlElement* pElemTMSL=hRoot.FirstChild( "TMSLimits" ).Element();
		if (pElemTMSL){ // le bloc TMSLimits n'est pas obligatoire, mais s'il est là, il doit y avoir tous les champs.
			TiXmlHandle hTMSL(pElem);
			TiXmlElement* pElemTMSL = hTMSL.FirstChild("minTileRow").Element();
			if (!pElemTMSL){
				LOGGER_ERROR(fileName <<" Level "<< id << ": Pas de minTileRow dans le bloc TMSLimits !!");
				return NULL;
			}
			if (!sscanf(pElemTMSL->GetText(),"%d",&minTileRow)){
				LOGGER_ERROR(fileName <<" Level "<< id <<": minTileRow=[" << pElemTMSL->GetText() <<"] n'est pas un entier.");
				return NULL;
			}

			pElemTMSL = hTMSL.FirstChild("maxTileRow").Element();
			if (!pElemTMSL){
				LOGGER_ERROR(fileName <<" Level "<< id << ": Pas de maxTileRow dans le bloc TMSLimits !!");
				return NULL;
			}
			if (!sscanf(pElemTMSL->GetText(),"%d",&maxTileRow)){
				LOGGER_ERROR(fileName <<" Level "<< id <<": maxTileRow=[" << pElemTMSL->GetText() <<"] n'est pas un entier.");
				return NULL;
			}

			pElemTMSL = hTMSL.FirstChild("minTileCol").Element();
			if (!pElemTMSL){
				LOGGER_ERROR("Level "<< id << ": Pas de minTileCol dans le bloc TMSLimits !!");
				return NULL;
			}
			if (!sscanf(pElemTMSL->GetText(),"%d",&minTileCol)){
				LOGGER_ERROR(fileName <<" Level "<< id <<": minTileCol=[" << pElemTMSL->GetText() <<"] n'est pas un entier.");
				return NULL;
			}

			pElemTMSL = hTMSL.FirstChild("maxTileCol").Element();
			if (!pElemTMSL){
				LOGGER_ERROR(fileName <<" Level "<< id << ": Pas de maxTileCol dans le bloc TMSLimits !!");
				return NULL;
			}
			if (!sscanf(pElemTMSL->GetText(),"%d",&maxTileCol)){
				LOGGER_ERROR(fileName <<" Level "<< id <<": maxTileCol=[" << pElemTMSL->GetText() <<"] n'est pas un entier.");
				return NULL;
			}
		}
		
		Level *TL = new Level(*tm, channels, baseDir, tilesPerWidth, tilesPerHeight,
				maxTileRow,  minTileRow, maxTileCol, minTileCol, pathDepth, format);
		
		levels.insert(std::pair<std::string, Level *> (id, TL));
	}// boucle sur les levels

	if (levels.size()==0){
		LOGGER_ERROR("Aucun level n'a pu être chargé pour la pyramide "<< fileName);
		return NULL;
	}

	Pyramid *pyr = new Pyramid(levels, *tms, format, channels);
	return pyr;

}// buildPyramid()

Layer * buildLayer(std::string fileName, std::map<std::string, TileMatrixSet*> &tmsList, bool reprojectionCapability){
	LOGGER_INFO("	Ajout du layer " << fileName);
	std::string id;
	std::string title="";
	std::string abstract="";
	std::vector<std::string> keyWords;
	std::string style;
	std::vector<std::string> styles;
	double minRes;
	double maxRes;
	std::vector<std::string> WMSCRSList;
	bool opaque;
	std::string authority="";
	std::string resampling;
	Pyramid* pyramid;
	GeographicBoundingBoxWMS geographicBoundingBox;
	BoundingBoxWMS boundingBox;

	TiXmlDocument doc(fileName.c_str());
	if (!doc.LoadFile()){
		LOGGER_ERROR("Ne peut pas charger le fichier " << fileName);
		return NULL;
	}

	TiXmlHandle hDoc(&doc);
	TiXmlElement* pElem;
	TiXmlHandle hRoot(0);

	pElem=hDoc.FirstChildElement().Element(); //recuperation de la racine.
	if (!pElem){
		LOGGER_ERROR(fileName << " impossible de recuperer la racine.");
		return NULL;
	}
	if (strcmp(pElem->Value(),"layer")){
		LOGGER_ERROR(fileName << " La racine n'est pas un layer.");
		return NULL;
	}
	hRoot=TiXmlHandle(pElem);

	unsigned int idBegin=fileName.rfind("/");
	if (idBegin == std::string::npos){
		idBegin=0;
	}
	unsigned int idEnd=fileName.rfind(".lay");
	if (idEnd == std::string::npos){
		idEnd=fileName.rfind(".LAY");
		if (idEnd == std::string::npos){
			idEnd=fileName.size();
		}
	}
	id=fileName.substr(idBegin+1, idEnd-idBegin-1);

	pElem=hRoot.FirstChild("title").Element();
	if (pElem) title=pElem->GetText();

	pElem=hRoot.FirstChild("abstract").Element();
	if (pElem) abstract=pElem->GetText();


	for (pElem=hRoot.FirstChild("keywordList").FirstChild("keyword").Element(); pElem; pElem=pElem->NextSiblingElement("keyword")){
		std::string keyword(pElem->GetText());
		keyWords.push_back(keyword);
	}

	pElem=hRoot.FirstChild("style").Element();
	if (!pElem){
		LOGGER_ERROR("Pas de style => style = " << DEFAULT_STYLE);
		style = DEFAULT_STYLE;
	}else{
		style = pElem->GetText();
	}
	styles.push_back(style);

	pElem = hRoot.FirstChild("minRes").Element();
	if (!pElem){
		minRes=0.;
	}else if (!sscanf(pElem->GetText(),"%lf",&minRes)){
		LOGGER_ERROR("La resolution min est inexploitable:[" << pElem->GetText() << "]");
		return NULL;
	}

	pElem = hRoot.FirstChild("maxRes").Element();
	if (!pElem){
		maxRes=0.;
	}else if (!sscanf(pElem->GetText(),"%lf",&maxRes)){
		LOGGER_ERROR("La resolution max est inexploitable:[" << pElem->GetText() << "]");
		return NULL;
	}
	// EX_GeographicBoundingBox
        pElem = hRoot.FirstChild("EX_GeographicBoundingBox").Element();
        if (!pElem){
                LOGGER_ERROR("Pas de geographicBoundingBox = ");
		return NULL;
        }else{
		// westBoundLongitude
		pElem = hRoot.FirstChild("EX_GeographicBoundingBox").FirstChild("westBoundLongitude").Element();
		if (!pElem){
			LOGGER_ERROR("Pas de westBoundLongitude");
                        return NULL;
		}
		else if (!sscanf(pElem->GetText(),"%lf",&geographicBoundingBox.minx)){
                        LOGGER_ERROR("Le westBoundLongitude est inexploitable:[" << pElem->GetText() << "]");
                        return NULL;
                }
		// southBoundLatitude
		pElem = hRoot.FirstChild("EX_GeographicBoundingBox").FirstChild("southBoundLatitude").Element();
                if (!pElem){
                        LOGGER_ERROR("Pas de southBoundLatitude");
                        return NULL;
                }
                if (!sscanf(pElem->GetText(),"%lf",&geographicBoundingBox.miny)){
                        LOGGER_ERROR("Le southBoundLatitude est inexploitable:[" << pElem->GetText() << "]");
                        return NULL;
                }
		// eastBoundLongitude
		pElem = hRoot.FirstChild("EX_GeographicBoundingBox").FirstChild("eastBoundLongitude").Element();
                if (!pElem){
                        LOGGER_ERROR("Pas de eastBoundLongitude");
                        return NULL;
                }
                if (!sscanf(pElem->GetText(),"%lf",&geographicBoundingBox.maxx)){
                        LOGGER_ERROR("Le eastBoundLongitude est inexploitable:[" << pElem->GetText() << "]");
                        return NULL;
                }
		// northBoundLatitude
		pElem = hRoot.FirstChild("EX_GeographicBoundingBox").FirstChild("northBoundLatitude").Element();
                if (!pElem){
                        LOGGER_ERROR("Pas de northBoundLatitude");
                        return NULL;
                }
                if (!sscanf(pElem->GetText(),"%lf",&geographicBoundingBox.maxy)){
                        LOGGER_ERROR("Le northBoundLatitude est inexploitable:[" << pElem->GetText() << "]");
                        return NULL;
                }
        }

	pElem = hRoot.FirstChild("boundingBox").Element();
	if (!pElem){
		LOGGER_ERROR("Pas de BoundingBox");
	}else{
		std::string tmp;
		tmp=pElem->Attribute("CRS");
		if (tmp.c_str()==0){
			LOGGER_ERROR("Le CRS est inexploitable:[" << pElem->GetText() << "]");
                        return NULL;
		}
		boundingBox.srs=pElem->Attribute("CRS");
		if (!sscanf(pElem->Attribute("minx"),"%lf",&boundingBox.minx)){
			LOGGER_ERROR("Le minx est inexploitable:[" << pElem->Attribute("minx") << "]");
			return NULL;
		}
                if (!sscanf(pElem->Attribute("miny"),"%lf",&boundingBox.miny)){
                        LOGGER_ERROR("Le miny est inexploitable:[" << pElem->Attribute("miny") << "]");
                        return NULL;
                }
                if (!sscanf(pElem->Attribute("maxx"),"%lf",&boundingBox.maxx)){
                        LOGGER_ERROR("Le maxx est inexploitable:[" << pElem->Attribute("maxx") << "]");
                        return NULL;
                }
                if (!sscanf(pElem->Attribute("maxy"),"%lf",&boundingBox.maxy)){
                        LOGGER_ERROR("Le maxy est inexploitable:[" << pElem->Attribute("maxy") << "]");
                        return NULL;
                }
	}

	if (reprojectionCapability==true){
		for (pElem=hRoot.FirstChild("WMSCRSList").FirstChild("WMSCRS").Element(); pElem; pElem=pElem->NextSiblingElement("WMSCRS")){
			std::string str_crs(pElem->GetText());
			// On verifie que la CRS figure dans la liste des CRS de proj4 (sinon, le serveur n est pas capable de la gerer)
			CRS crs(str_crs);
			if (!crs.isProj4Compatible())
				LOGGER_WARN("Le CRS "<<str_crs<<" n est pas reconnu par Proj4 et n est donc par ajoute aux CRS de la couche");
			else{
				LOGGER_INFO("		Ajout du crs "<<str_crs);
				WMSCRSList.push_back(str_crs);
			}
		}
	}
	if (WMSCRSList.size()==0){
		LOGGER_WARN(fileName << ": Aucun CRS autorisé pour le WMS");
	}

	pElem=hRoot.FirstChild("opaque").Element();
	if (!pElem){
		LOGGER_ERROR("Pas de opaque => opaque = " << DEFAULT_OPAQUE);
		opaque = DEFAULT_OPAQUE;
	}else{
		std::string opaStr=pElem->GetText();
		if (opaStr=="true"){
			opaque = true;
		}else if(opaStr=="false"){
			opaque = false;
		}else{
			LOGGER_ERROR("le param opaque n'est pas exploitable:[" << opaStr <<"]");
			return NULL;
		}
	}

	pElem=hRoot.FirstChild("authority").Element();
	if (pElem) authority=pElem->GetText();

	pElem=hRoot.FirstChild("resampling").Element();
	if (!pElem){
		LOGGER_ERROR("Pas de resampling => resampling = " << DEFAULT_RESAMPLING);
		resampling = DEFAULT_RESAMPLING;
	}else{
		resampling = pElem->GetText();
	}

	pElem=hRoot.FirstChild("pyramid").Element();
	if (pElem){
		pyramid = buildPyramid(pElem->GetText(), tmsList);
		if (!pyramid){
                        LOGGER_ERROR("La pyramide " << pElem->GetText() << " ne peut être chargée");
                        return NULL;
                }
	}
	else{
		// FIXME: pas forcément critique si on a un cache d'une autre nature (jpeg2000 par exemple).
                LOGGER_ERROR("Aucune pyramide associee au layer "<< fileName);
                return NULL;
	}

	Layer *layer;

	layer = new Layer(id, title, abstract, keyWords, pyramid, styles, minRes, maxRes,
			WMSCRSList, opaque, authority, resampling,geographicBoundingBox,boundingBox);

	return layer;
}//buildLayer

bool ConfLoader::getTechnicalParam(std::string serverConfigFile, LogOutput& logOutput, std::string& logFilePrefix, int& logFilePeriod, LogLevel& logLevel, int& nbThread, bool& reprojectionCapability, std::string& servicesConfigFile, std::string &layerDir, std::string &tmsDir){
	std::cout<<"Chargement des parametres techniques depuis "<<serverConfigFile<<std::endl;
	TiXmlDocument doc(serverConfigFile);
	if (!doc.LoadFile()){
		std::cerr<<"Ne peut pas charger le fichier " << serverConfigFile<<std::endl;
		return false;
	}

	TiXmlHandle hDoc(&doc);
	TiXmlElement* pElem;
	TiXmlHandle hRoot(0);

	pElem=hDoc.FirstChildElement().Element(); //recuperation de la racine.
	if (!pElem){
		std::cerr<<serverConfigFile << " impossible de recuperer la racine."<<std::endl;
		return false;
	}
	if (strcmp(pElem->Value(), "serverConf")){
		std::cerr<<serverConfigFile << " La racine n'est pas un serverConf."<<std::endl;
		return false;
	}
	hRoot=TiXmlHandle(pElem);

	pElem=hRoot.FirstChild("logOutput").Element();
	std::string strLogOutput=(pElem->GetText());
        if (!pElem){
                std::cerr<<"Pas de logOutput => logOutput = " << DEFAULT_LOG_OUTPUT;
                logOutput = DEFAULT_LOG_OUTPUT;
        }else if (strLogOutput=="rolling_file") logOutput=ROLLING_FILE;
	else if (strLogOutput=="standard_output_stream_for_errors") logOutput=STANDARD_OUTPUT_STREAM_FOR_ERRORS;
	else{
		std::cerr<<"Le logOutput [" << pElem->GetText() <<"]  est inconnu."<<std::endl;
                return false;
	}

	pElem=hRoot.FirstChild("logFilePrefix").Element();
        if (!pElem){
                std::cerr<<"Pas de logFilePrefix => logFilePrefix = " << DEFAULT_LOG_FILE_PREFIX;
                logFilePrefix = DEFAULT_LOG_FILE_PREFIX;
        }else{
                logFilePrefix=pElem->GetText();
        }
	pElem=hRoot.FirstChild("logFilePeriod").Element();
        if (!pElem){
                std::cerr<<"Pas de logFilePeriod => logFilePeriod = " << DEFAULT_LOG_FILE_PERIOD;
                logFilePeriod = DEFAULT_LOG_FILE_PERIOD;
        }else if (!sscanf(pElem->GetText(),"%d",&logFilePeriod))  {
		std::cerr<<"Le logFilePeriod [" << pElem->GetText() <<"]  n'est pas un entier."<<std::endl;	
                return false;
        }

	pElem=hRoot.FirstChild("logLevel").Element();
	std::string strLogLevel(pElem->GetText());
        if (!pElem){
                std::cerr<<"Pas de logLevel => logLevel = " << DEFAULT_LOG_LEVEL;
                logLevel = DEFAULT_LOG_LEVEL;
        }else if (strLogLevel=="fatal") logLevel=FATAL;
	else if (strLogLevel=="error") logLevel=ERROR;
	else if (strLogLevel=="warn") logLevel=WARN; 
	else if (strLogLevel=="info") logLevel=INFO;
        else if (strLogLevel=="debug") logLevel=DEBUG;
	else{
               	std::cerr<<"Le logLevel [" << pElem->GetText() <<"]  est inconnu."<<std::endl;
               	return false;
        }
		
	pElem=hRoot.FirstChild("nbThread").Element();
	if (!pElem){
		std::cerr<<"Pas de nbThread => nbThread = " << DEFAULT_NB_THREAD<<std::endl;
		nbThread = DEFAULT_NB_THREAD;
	}else if (!sscanf(pElem->GetText(),"%d",&nbThread)){
		std::cerr<<"Le nbThread [" << pElem->GetText() <<"] n'est pas un entier."<<std::endl;
		return false;
	}
	
	pElem=hRoot.FirstChild("reprojectionCapability").Element();
        if (!pElem){
                std::cerr<<"Pas de reprojectionCapability => reprojectionCapability = true"<<std::endl;
                reprojectionCapability = true;
        }else{
		std::string strReprojection(pElem->GetText());
		if (strReprojection=="true") reprojectionCapability=true;
		else if (strReprojection=="false") reprojectionCapability=false;
		else{
			std::cerr<<"Le reprojectionCapability [" << pElem->GetText() <<"] n'est pas un booleen."<<std::endl;
                	return false;
		}
        }

	pElem=hRoot.FirstChild("servicesConfigFile").Element();
        if (!pElem){
                std::cerr<<"Pas de servicesConfigFile => servicesConfigFile = " << DEFAULT_SERVICES_CONF_PATH <<std::endl;
                servicesConfigFile = DEFAULT_SERVICES_CONF_PATH;
        }else{
                servicesConfigFile=pElem->GetText();
        }

	pElem=hRoot.FirstChild("layerDir").Element();
	if (!pElem){
		std::cerr<<"Pas de layerDir => layerDir = " << DEFAULT_LAYER_DIR<<std::endl;
		layerDir = DEFAULT_LAYER_DIR;
	}else{
		layerDir=pElem->GetText();
	}

	pElem=hRoot.FirstChild("tileMatrixSetDir").Element();
	if (!pElem){
		std::cerr<<"Pas de tileMatrixSetDir => tileMatrixSetDir = " << DEFAULT_TMS_DIR<<std::endl;
		tmsDir = DEFAULT_TMS_DIR;
	}else{
		tmsDir=pElem->GetText();
	}
	
	// Définition de la variable PROJ_LIB à partir de la configuration
	std::string projDir;
	
	char* projDirEnv;
	bool absolut=true;
	pElem=hRoot.FirstChild("projConfigDir").Element();
	if (!pElem){
		std::cerr<<"Pas de projConfigDir => projConfigDir = " << DEFAULT_PROJ_DIR<<std::endl;
		char* pwdBuff = (char*) malloc(PATH_MAX);
		getcwd(pwdBuff,PATH_MAX);
		projDir = std::string(pwdBuff);
		projDir.append("/").append(DEFAULT_PROJ_DIR);
		free(pwdBuff);
	}else{
		projDir=pElem->GetText();
		//Gestion des chemins relatif
		if (projDir.compare(0,1,"/") != 0){
			absolut=false;
			char* pwdBuff = (char*) malloc(PATH_MAX);
			getcwd(pwdBuff,PATH_MAX);
			std::string pwdBuffStr = std::string(pwdBuff);
			pwdBuffStr.append("/");
			projDir.insert(0,pwdBuffStr);
			free(pwdBuff);
		}
	}
	projDirEnv = (char*) malloc(8+2+PATH_MAX);
	strcat(projDirEnv,"PROJ_LIB=");
	strcat(projDirEnv,projDir.c_str());
	
	if (putenv(projDirEnv)!=0) {
	  std::cerr<<"ERREUR FATALE : Impossible de définir le chemin pour proj "<< projDir<<std::endl;
	  return false;
	}
	

	return true;
}//getTechnicalParam


bool ConfLoader::buildTMSList(std::string tmsDir,std::map<std::string, TileMatrixSet*> &tmsList){
	LOGGER_INFO("CHARGEMENT DES TMS");

	// lister les fichier du répertoire tmsDir
	std::vector<std::string> tmsFiles;
	std::string tmsFileName;
	struct dirent *fileEntry;
	DIR *dir;
	if ((dir = opendir(tmsDir.c_str())) == NULL){
		LOGGER_FATAL("Le répertoire des TMS " << tmsDir << " n'est pas accessible.");
		return false;
	}
	while ((fileEntry = readdir(dir))){
		tmsFileName = fileEntry->d_name;
		if(tmsFileName.rfind(".tms")==tmsFileName.size()-4){
			tmsFiles.push_back(tmsDir+"/"+tmsFileName);
		}
	}
	closedir(dir);

	if (tmsFiles.empty()){
		// FIXME:
		// Aucun TMS présents. Ce n'est pas nécessairement grave si le serveur
		// ne sert pas pour le WMTS et qu'on exploite pas de cache tuilé.
		// Cependant pour le moment (07/2010) on ne gère que des caches tuilés
		LOGGER_FATAL("Aucun fichier *.tms dans le répertoire " << tmsDir);
		return false;
	}

	// générer les TMS décrits par les fichiers.
	for (unsigned int i=0; i<tmsFiles.size(); i++){
		TileMatrixSet * tms;
		tms = buildTileMatrixSet(tmsFiles[i]);
		if (tms){
			tmsList.insert( std::pair<std::string, TileMatrixSet *> (tms->getId(), tms));
		}else{
			LOGGER_ERROR("Ne peut charger le tms: " << tmsFiles[i]);
		}
	}

	if (tmsList.size()==0){
		LOGGER_FATAL("Aucun TMS n'a pu être chargé!");
		return false;
	}
	
	LOGGER_INFO("NOMBRE DE TMS CHARGES : "<<tmsList.size());

	return true;
}

bool ConfLoader::buildLayersList(std::string layerDir,std::map<std::string, TileMatrixSet*> &tmsList, std::map<std::string,Layer*> &layers, bool reprojectionCapability){
	LOGGER_INFO("CHARGEMENT DES LAYERS");
	// lister les fichier du répertoire layerDir
	std::vector<std::string> layerFiles;
	std::string layerFileName;
	struct dirent *fileEntry;
	DIR *dir;
	if ((dir = opendir(layerDir.c_str())) == NULL){
		LOGGER_FATAL("Le répertoire " << layerDir << " n'est pas accessible.");
		return false;
	}
	while ((fileEntry = readdir(dir))){
		layerFileName = fileEntry->d_name;
		if(layerFileName.rfind(".lay")==layerFileName.size()-4){
			layerFiles.push_back(layerDir+"/"+layerFileName);
		}
	}
	closedir(dir);

	if (layerFiles.empty()){
		LOGGER_FATAL("Aucun fichier *.lay dans le répertoire " << layerDir);
		LOGGER_FATAL("Le serveur n'a aucune données à servir. Dommage...");
		return false;
	}

	// générer les Layers décrits par les fichiers.
	for (unsigned int i=0; i<layerFiles.size(); i++){
		Layer * layer;
		layer = buildLayer(layerFiles[i], tmsList, reprojectionCapability);
		if (layer){
			layers.insert( std::pair<std::string, Layer *> (layer->getId(), layer));
		}else{
			LOGGER_ERROR("Ne peut charger le layer: " << layerFiles[i]);
		}
	}

	if (layers.size()==0){
		LOGGER_FATAL("Aucun layer n'a pu être chargé!");
		return false;
	}

	LOGGER_INFO("NOMBRE DE LAYERS CHARGES : "<<layers.size());
	return true;
}

ServicesConf * ConfLoader::buildServicesConf(std::string servicesConfigFile){
	LOGGER_INFO("Construction de la configuration des services depuis "<<servicesConfigFile);
	TiXmlDocument doc(servicesConfigFile);
	if (!doc.LoadFile()){
		LOGGER_ERROR("Ne peut pas charger le fichier " << servicesConfigFile);
		return NULL;
	}

	TiXmlHandle hDoc(&doc);
	TiXmlElement* pElem;
	TiXmlHandle hRoot(0);

	pElem=hDoc.FirstChildElement().Element(); //recuperation de la racine.
	if (!pElem){
		LOGGER_ERROR(servicesConfigFile << " impossible de recuperer la racine.");
		return NULL;
	}
	if (pElem->ValueStr() != "servicesConf"){
		LOGGER_ERROR(servicesConfigFile << " La racine n'est pas un servicesConf.");
		return NULL;
	}
	hRoot=TiXmlHandle(pElem);

	std::string name="";
	std::string title="";
	std::string abstract="";
	std::vector<std::string> keyWords;
	std::string serviceProvider;
	std::string fee;
	std::string accessConstraint;
	unsigned int maxWidth;
	unsigned int maxHeight;
	std::vector<std::string> formatList;
	std::string serviceType;
	std::string serviceTypeVersion;
	std::vector<std::string> applicationProfileList;

	pElem=hRoot.FirstChild("name").Element();
	if (pElem) name = pElem->GetText();

	pElem=hRoot.FirstChild("title").Element();
	if (pElem) title = pElem->GetText();

	pElem=hRoot.FirstChild("abstract").Element();
	if (pElem) abstract = pElem->GetText();


	for (pElem=hRoot.FirstChild("keywordList").FirstChild("keyword").Element(); pElem; pElem=pElem->NextSiblingElement("keyword")){
		std::string keyword(pElem->GetText());
		keyWords.push_back(keyword);
	}

	pElem=hRoot.FirstChild("serviceProvider").Element();
	if (pElem) serviceProvider = pElem->GetText();

	pElem=hRoot.FirstChild("fee").Element();
	if (pElem) fee = pElem->GetText();

	pElem=hRoot.FirstChild("accessConstraint").Element();
	if (pElem) accessConstraint = pElem->GetText();

	pElem = hRoot.FirstChild("maxWidth").Element();
	if (!pElem){
		maxWidth=MAX_IMAGE_WIDTH;
	}else if (!sscanf(pElem->GetText(),"%d",&maxWidth)){
		LOGGER_ERROR(servicesConfigFile << "Le maxWidth est inexploitable:[" << pElem->GetText() << "]");
		return NULL;
	}

	pElem = hRoot.FirstChild("maxHeight").Element();
	if (!pElem){
		maxHeight=MAX_IMAGE_HEIGHT;
	}else if (!sscanf(pElem->GetText(),"%d",&maxHeight)){
		LOGGER_ERROR(servicesConfigFile << "Le maxHeight est inexploitable:[" << pElem->GetText() << "]");
		return false;
	}

	for (pElem=hRoot.FirstChild("formatList").FirstChild("format").Element(); pElem; pElem=pElem->NextSiblingElement("format")){
		std::string format(pElem->GetText());
		if (format != "image/jpeg" &&
			format != "image/png"  &&
			format != "image/tiff" &&
			format != "image/x-bil;bits=32" &&
			format != "image/gif"){
			LOGGER_ERROR(servicesConfigFile << "le format d'image [" << format << "] n'est pas un type MIME");
		}else{
			formatList.push_back(format);
		}
	}

	pElem=hRoot.FirstChild("serviceType").Element();
        if (pElem) serviceType = pElem->GetText();
	pElem=hRoot.FirstChild("serviceTypeVersion").Element();
        if (pElem) serviceTypeVersion = pElem->GetText();

	ServicesConf * servicesConf;
	servicesConf = new ServicesConf(name, title, abstract, keyWords,serviceProvider, fee,
			accessConstraint, maxWidth, maxHeight, formatList, serviceType, serviceTypeVersion);

	return servicesConf;
}
