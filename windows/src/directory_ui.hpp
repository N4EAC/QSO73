#pragma once
void refreshDirectory() {
  if(directoryFooter)SetWindowTextW(directoryFooter,wide(directoryError.empty()?"Grid centers are approximate. Unknown locations remain listed without a pin. ADIF Contact Log is separate.":directoryError).c_str());
  contacts.clear();directoryRows.clear();favoriteRows.clear();
  if(directoryList)SendMessageW(directoryList,LB_RESETCONTENT,0,0);
  if(favoriteList)SendMessageW(favoriteList,LB_RESETCONTENT,0,0);
  for(auto &pair:stationDirectory.records) {
    auto &c=pair.second;contacts.insert(c.call);directoryRows.push_back(c.call);
    std::string line=c.call+"  |  "+(c.grid.empty()?"Grid unknown":c.grid);
    if(c.lastHeard>0)line+="  |  "+Contact::utc(std::time_t(c.lastHeard));
    if(directoryList)SendMessageW(directoryList,LB_ADDSTRING,0,reinterpret_cast<LPARAM>(wide(line).c_str()));
    if(c.favorite){favoriteRows.push_back(c.call);if(favoriteList)SendMessageW(favoriteList,LB_ADDSTRING,0,reinterpret_cast<LPARAM>(wide(line).c_str()));}
  }
  if(directoryList)for(size_t i=0;i<directoryRows.size();++i)if(directoryRows[i]==directorySelection)SendMessageW(directoryList,LB_SETCURSEL,i,0);
  if(favoriteList)for(size_t i=0;i<favoriteRows.size();++i)if(favoriteRows[i]==directorySelection)SendMessageW(favoriteList,LB_SETCURSEL,i,0);
}
void loadDirectory() {
  auto path=std::filesystem::path(base+L"station-directory.json");
  if(!std::filesystem::exists(path))return;
  try {
    std::ifstream file(path,std::ios::binary);if(!file)throw std::runtime_error("Cannot read station directory");
    std::string data((std::istreambuf_iterator<char>(file)),{});Json json(data);stationDirectory=StationDirectory::parse(json);refreshDirectory();
  } catch(...) {directoryError="Saved contact directory could not be read. Original preserved; use Full reset to erase it.";}
}
void saveDirectory() {
  if(!directoryError.empty())throw std::runtime_error(directoryError);
  auto path=base+L"station-directory.json",temp=path+L".tmp";
  std::ofstream file(std::filesystem::path(temp),std::ios::binary);file<<stationDirectory.serialize();file.flush();
  if(!file)throw std::runtime_error("Cannot save contact directory");
  file.close();
  if(!MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))throw std::runtime_error("Cannot replace contact directory");
  refreshDirectory();
}
void rememberStation(const std::string &call,const std::string &wire,bool received) {
  if(!directoryError.empty())return;
  auto before=stationDirectory.serialize();
  stationDirectory.remember(call,settings.call,wire,received,epoch());
  if(before!=stationDirectory.serialize())saveDirectory();
}
void directoryCommand(int id) {
  if(id==DIRCLEAR || id==DIRRESET){
    auto prompt=id==DIRRESET?L"Erase the entire callsign directory, including ALL favorites? Completed ADIF contacts are kept in Contact Log.":L"Erase non-favorite contacts? Favorites will be kept.";
    if(MessageBoxW(win,prompt,L"QSO73 contact directory",MB_YESNO|MB_ICONWARNING|MB_DEFBUTTON2)!=IDYES)return;
    if(id==DIRRESET){stationDirectory.records.clear();directoryError.clear();}
    else {if(!directoryError.empty())throw std::runtime_error(directoryError);stationDirectory.clear();}
    directorySelection.clear();SetWindowTextW(directoryCall,L"Select a contact");SetWindowTextW(controls[DIRECTORYGRID],L"");
  } else {
    if(!directoryError.empty())throw std::runtime_error(directoryError);
    auto found=stationDirectory.records.find(directorySelection);
    if(found==stationDirectory.records.end())throw std::runtime_error("Select a contact or favorite first.");
    if(id==DIRSAVE){auto grid=qso::call(value(DIRECTORYGRID));if(!StationDirectory::validGrid(grid))throw std::runtime_error("Enter a valid Maidenhead grid or leave it blank.");found->second.grid=grid;}
    else if(id==DIRFAVORITE)found->second.favorite=!found->second.favorite;
    else if(id==DIRDELETE){if(MessageBoxW(win,wide("Delete "+directorySelection+" from contacts and favorites?").c_str(),L"Delete contact",MB_YESNO|MB_ICONWARNING|MB_DEFBUTTON2)!=IDYES)return;stationDirectory.records.erase(found);directorySelection.clear();SetWindowTextW(directoryCall,L"Select a contact");SetWindowTextW(controls[DIRECTORYGRID],L"");}
  }
  saveDirectory();
  if(!contacts.count(value(TO)))comboSet(TO,{"QST"},"QST");
  rebuildRooms();
}
void openContactMap() {
  if(!directoryError.empty())throw std::runtime_error(directoryError);
  auto module=GetModuleHandleW(nullptr);auto resource=FindResourceW(module,MAKEINTRESOURCEW(201),RT_RCDATA);
  if(!resource)throw std::runtime_error("Contact map resource is missing.");
  auto handle=LoadResource(module,resource);auto bytes=static_cast<const char*>(LockResource(handle));
  std::string html(bytes,SizeofResource(module,resource));
  Json payload(cJSON_CreateObject());cJSON_AddStringToObject(payload.p,"theme",settings.theme.c_str());
  Json directory(stationDirectory.serialize());cJSON_AddItemToObject(payload.p,"contacts",directory.p);directory.p=nullptr;
  auto data=payload.dump();
  for(auto pair:std::vector<std::pair<std::string,std::string>>{{"<","\\u003c"},{">","\\u003e"},{"&","\\u0026"}}){size_t p=0;while((p=data.find(pair.first,p))!=std::string::npos){data.replace(p,pair.first.size(),pair.second);p+=pair.second.size();}}
  auto token=html.find("__QSO73_DATA__");if(token==std::string::npos)throw std::runtime_error("Invalid map template");html.replace(token,std::string("__QSO73_DATA__").size(),data);
  wchar_t folder[MAX_PATH];if(!GetTempPathW(MAX_PATH,folder))throw std::runtime_error("Cannot locate temporary folder");
  auto path=std::wstring(folder)+L"QSO73-Contact-Map.html";
  std::ofstream file(std::filesystem::path(path),std::ios::binary);file<<html;file.close();if(!file)throw std::runtime_error("Cannot create contact map");
  if(INT_PTR(ShellExecuteW(win,L"open",path.c_str(),nullptr,nullptr,SW_SHOWNORMAL))<=32)throw std::runtime_error("Cannot open map in your browser");
}
