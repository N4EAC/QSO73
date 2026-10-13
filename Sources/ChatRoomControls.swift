import SwiftUI

struct ChatRoomControls: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var modem: Modem
    @ObservedObject var rooms: ChatRooms
    @State private var newConversation = ""
    @State private var topicDraft = ""
    @State private var showTopic = false
    @State private var showUsers = false
    private var ready: Bool { modem.attached && modem.audioConnected }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Conversation", selection: $rooms.selected) {
                    ForEach(rooms.conversations, id: \.self) { value in
                        Text((value == "radio" ? "Radio Chat" : value) + ((rooms.unread[value] ?? 0) > 0 ? " (\(rooms.unread[value]!))" : "")).tag(value)
                    }
                }.frame(width: 240)
                TextField("#channel or callsign", text: $newConversation).textFieldStyle(.roundedBorder).frame(width: 160)
                Button("Open / Join") {
                    do {
                        if newConversation.hasPrefix("#") {
                            try rooms.join(newConversation)
                            if ready { modem.sendRoom("", room: rooms.selected, kind: "join") }
                        } else { try rooms.direct(newConversation) }
                        newConversation = ""
                    } catch { workspace.error = error.localizedDescription }
                }
                if rooms.selected.hasPrefix("#") {
                    Button(rooms.joined.contains(rooms.selected) ? "Leave" : "Join") {
                        let room = rooms.selected
                        if rooms.joined.contains(room) {
                            if ready { modem.sendRoom("", room: room, kind: "leave") }
                            rooms.leave(room)
                        } else {
                            try? rooms.join(room)
                            if ready { modem.sendRoom("", room: room, kind: "join") }
                        }
                    }
                    Button("Topic…") { topicDraft = rooms.topics[rooms.selected] ?? ""; showTopic = true }
                        .disabled(!ready || !rooms.joined.contains(rooms.selected))
                    Button("Users…") { showUsers = true }
                        .popover(isPresented: $showUsers) {
                            TimelineView(.periodic(from: .now, by: 5)) { clock in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Users in \(rooms.selected)").font(.headline)
                                    Text("Stations heard in this channel within 10 minutes; this is not a confirmed online list.").font(.caption).foregroundStyle(.secondary)
                                    ForEach(rooms.users(in: rooms.selected, local: workspace.settings.callsign, now: clock.date), id: \.self) { call in
                                        Button(call) { try? rooms.direct(call); showUsers = false }
                                    }
                                }.padding().frame(width: 300)
                            }
                        }
                }
                Spacer(minLength: 0)
            }
            if rooms.selected.hasPrefix("#") {
                Text("Topic: " + (rooms.topics[rooms.selected].flatMap { $0.isEmpty ? nil : $0 } ?? "No topic set"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if rooms.joined.contains(rooms.selected) {
                    ChannelAnnouncementControls(room: rooms.selected, announcements: modem.channelAnnouncements) { workspace.error = $0 }
                }
            }
        }
        .sheet(isPresented: $showTopic) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Topic for \(rooms.selected)").font(.headline)
                TextField("Channel topic (blank clears it)", text: $topicDraft).textFieldStyle(.roundedBorder)
                Text("Any joined station may set a topic. The latest received topic is shown; there is no central channel server.").font(.caption)
                HStack {
                    Button("Cancel") { showTopic = false }
                    Spacer()
                    Button("Transmit Topic") {
                        modem.error = nil; modem.sendRoom(topicDraft, room: rooms.selected, kind: "topic")
                        if modem.error == nil { showTopic = false }
                    }.disabled(!ready || (try? RoomEnvelope(kind: "topic", room: rooms.selected, text: topicDraft).encoded()) == nil)
                }
            }.padding(24).frame(width: 440)
        }
    }
}
