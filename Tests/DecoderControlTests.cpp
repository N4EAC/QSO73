#include "../vendor/modem73/control_port.hh"
#include <cassert>
#include <array>

static std::string read_frame(int fd) {
    std::array<uint8_t, 4> h{};
    assert(recv(fd, h.data(), 4, MSG_WAITALL) == 4);
    size_t n = (size_t(h[0])<<24)|(size_t(h[1])<<16)|(size_t(h[2])<<8)|h[3];
    assert(n > 0 && n < 65536);
    std::string s(n, '\0');
    assert(recv(fd, s.data(), n, MSG_WAITALL) == static_cast<ssize_t>(n));
    return s;
}
int main() {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in addr{}; addr.sin_family=AF_INET; addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0);
    socklen_t size=sizeof(addr); assert(getsockname(fd, reinterpret_cast<sockaddr*>(&addr), &size)==0);
    int port=ntohs(addr.sin_port); close(fd);
    std::atomic<bool> decoding{false};
    ControlPort::TNCInterface iface;
    iface.is_decoding=[&] {return decoding.load();};
    iface.get_status=[&] { auto j=cJSON_CreateObject(); cJSON_AddBoolToObject(j,"ok",true); cJSON_AddBoolToObject(j,"decoding",decoding); return j; };
    ControlPort ctrl(port,"127.0.0.1",iface); assert(ctrl.start());
    fd=socket(AF_INET,SOCK_STREAM,0);
    timeval timeout{2,0}; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    assert(connect(fd,reinterpret_cast<sockaddr*>(&addr),sizeof(addr))==0);
    auto expect=[&](bool value) {
        for(int i=0;i<20;++i) {
            auto s=read_frame(fd); cJSON* j=cJSON_Parse(s.c_str()); assert(j);
            auto event=cJSON_GetObjectItem(j,"event"); auto state=cJSON_GetObjectItem(j,"decoding");
            bool match=cJSON_IsString(event)&&std::string(event->valuestring)=="decoder_state"&&cJSON_IsBool(state)&&(bool(cJSON_IsTrue(state))==value);
            cJSON_Delete(j); if(match)return;
        }
        assert(false);
    };
    expect(false); decoding=true; expect(true);
    // A command response and decoder heartbeat share the same framing safely.
    std::string command="{\"cmd\":\"get_status\"}";
    std::array<uint8_t,4> h{0,0,0,static_cast<uint8_t>(command.size())};
    assert(send(fd,h.data(),h.size(),0)==4); assert(send(fd,command.data(),command.size(),0)==static_cast<ssize_t>(command.size()));
    bool replied=false;
    for(int i=0;i<20&&!replied;++i){auto s=read_frame(fd);auto j=cJSON_Parse(s.c_str());assert(j);replied=cJSON_IsTrue(cJSON_GetObjectItem(j,"ok"));cJSON_Delete(j);}
    assert(replied); decoding=false; expect(false); close(fd); ctrl.stop();
    std::cout<<"PASS: live decoder heartbeat, active/idle transitions and interleaved control responses\n";
}
