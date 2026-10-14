#include "contact_log.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
int main(){
 Contact c{"id","k1abc/p","n4eac-7","FN42","EL87","7.105","20261014 235950","20261015 000005","","","A<B> & test"};c.validate();auto data=Contact::exportADIF({c});std::ofstream("/tmp/qso73-contact-windows.adi")<<data;
 assert(data.find("<QSO_DATE_OFF:8>20261015")!=data.npos&&data.find("<MODE:3>PKT")!=data.npos&&data.find("<BAND:3>40m")!=data.npos);
 for(auto frequency:{"nan","7.1MHz","0","27.5"}){auto bad=c;bad.frequency=frequency;bool rejected=false;try{bad.validate();}catch(...){rejected=true;}assert(rejected);}
 for(auto time:{"20260230 120000","20261014 246000","20251314 120000"}){bool rejected=false;try{Contact::timestamp(time);}catch(...){rejected=true;}assert(rejected);}
 auto j=c.json();auto roundtrip=Contact::from(j);assert(roundtrip.adif()==c.adif());std::cout<<"PASS: Windows ADIF fields, UTC rollover, invalid calendar/frequency rejection and saved contact roundtrip\n";
}
