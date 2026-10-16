#pragma once
#include "protocol.hpp"
#include <regex>
#include <cmath>
namespace qso {
struct StationContact {
  std::string call, grid;
  bool favorite = false;
  double lastHeard = 0;
};
struct StationDirectory {
  std::map<std::string, StationContact> records;
  static bool validGrid(const std::string &grid) {
    return grid.empty() || std::regex_match(grid,std::regex("[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?"));
  }
  static std::string reportedGrid(const std::string &text,const std::string &source) {
    if(text.rfind("BEACON "+source+" ",0)==0) {
      auto start=8+source.size();auto grid=text.substr(start,text.find(' ',start)-start);
      if(validGrid(grid))return grid;
    }
    if(text.rfind("~Q73P:",0)==0) {
      try {Json j(text.substr(6));if(j.str("k")=="reply" && j.str("call")==source && validGrid(j.str("grid"))) return j.str("grid");}catch(...){}
    }
    return {};
  }
  void remember(const std::string &raw,const std::string &own,const std::string &wire={},bool received=false,double time=0) {
    auto who=qso::call(raw);
    if(!station(who)||who==qso::call(own)||who=="QST"||who=="CQ"||who=="ALL")return;
    auto &c=records[who];c.call=who;
    if(received)c.lastHeard=time;
    auto grid=reportedGrid(wire,who);if(!grid.empty())c.grid=grid;
  }
  void clear(){for(auto i=records.begin();i!=records.end();)if(!i->second.favorite)i=records.erase(i);else ++i;}
  std::string serialize() const {
    Json data(cJSON_CreateArray());
    for(auto &pair:records){auto &c=pair.second;auto j=cJSON_CreateObject();cJSON_AddStringToObject(j,"call",c.call.c_str());cJSON_AddStringToObject(j,"grid",c.grid.c_str());cJSON_AddBoolToObject(j,"favorite",c.favorite);cJSON_AddNumberToObject(j,"lastHeard",c.lastHeard);cJSON_AddItemToArray(data.p,j);}
    return data.dump(true);
  }
  static StationDirectory parse(const Json &data) {
    if(!cJSON_IsArray(data.p))throw std::runtime_error("Invalid station directory");
    StationDirectory out;cJSON *item;
    cJSON_ArrayForEach(item,data.p){Json j(cJSON_Duplicate(item,1));auto who=j.str("call");auto grid=j.str("grid");if(!station(who)||qso::call(who)!=who||!validGrid(grid)||out.records.count(who)||!std::isfinite(j.num("lastHeard"))||j.num("lastHeard")<0||j.num("lastHeard")>4102444800)throw std::runtime_error("Invalid station directory record");out.records[who]={who,grid,cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(item,"favorite")) != 0,j.num("lastHeard")};}
    return out;
  }
};
}
