import DeckhandKit
import SwiftUI

/// What this session is to keep in mind, carried in front of every message it is sent.
///
/// The pane is a page, not a form: one paragraph you tap to change, what it costs underneath, and
/// nothing else. Everything about *how* it is carried is the Mac's — this only shows what is
/// standing, which is the point of having it on screen at all. The words ride on the prompt they
/// are attached to and carry exactly its authority: typed into the pane they arrive as JJ, down
/// the peer socket they arrive labelled as another agent, like everything else on that route.
///
/// **The writing happens in `Editor`, on a sheet, and that is not laziness — it is the one
/// arrangement that works.** A field on this pane would put a second talk control on a screen
/// that already floats one over it: two `TalkControl`s reading the same recorder, both live, one
/// filling a box and the other sending to the session. A sheet covers the mark, so the only
/// control listening is the one under your thumb — and `Editor` already opens focused with the
/// keyboard up, which is what "a big field you can dictate into" wanted in the first place.
///
/// Its own loading rather than an `AppModel` extension, which is where every other call in this
/// app lives: `deckhand/` sits on its 16-file gate, this is one screen's own state, and nothing
/// else in the app wants it. It still goes through `model.run`, so a Mac that will not answer
/// says so in the same status line as everything else.
struct OrdersView: View {
    @Bindable var model: AppModel
    let session: Session
    /// The session page's own recorder, lent so the paragraph can be said rather than typed. Nil
    /// where there is nothing to lend, and then it is typed the way any other field would be.
    var say: Dictation?
    @State private var orders = Orders()
    @State private var editing = false
    /// Asked for once, when the pane is built. Nothing but this phone writes it, so a poll would
    /// be a request every few seconds to be told what it already knows.
    @State private var asked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.small) {
                lead
                written
                foot
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.large)
            .padding(.bottom, Spacing.extraLarge)
        }
        .frame(maxHeight: .infinity)
        .fadingEdges()
        // Room at the end for the mark that floats over this.
        .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
        .task { await load() }
        .sheet(isPresented: $editing) {
            Editor(words: orders.text, target: "Orders", say: say) { edited in
                editing = false
                Task { await keep(edited) }
            }
        }
    }

    /// What this pane does, in one line, because a paragraph that goes into every message is not
    /// a thing to discover by watching a session behave oddly.
    private var lead: some View {
        Text("In front of every message \(session.name) is sent, until you change it.")
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, Spacing.xxs)
    }

    /// The orders as they stand. The whole card is the way in — the empty one says so out loud,
    /// because a card you tap and nothing else on the page is a card nobody taps.
    private var written: some View {
        Button { editing = true } label: {
            Card {
                if orders.inForce {
                    Text(orders.text)
                        .font(Typography.prose)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Nothing standing. Tap to write it.")
                        .font(Typography.prose)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("orders-card")
        .accessibilityLabel(orders.inForce ? "Standing orders: \(orders.text)" : "No standing orders")
        .accessibilityHint("Opens the field to change them")
    }

    /// What they cost, and the one way to stop them. The count is against the Mac's own cap, never
    /// against a number compiled in here — see `Orders.limit`.
    @ViewBuilder private var foot: some View {
        if orders.inForce {
            HStack(spacing: Spacing.small) {
                Text(spent)
                Spacer(minLength: Spacing.extraSmall)
                Button("Clear") { Task { await keep("") } }
                    .font(Typography.hint)
                    .tint(Palette.textSecondary)
                    .accessibilityIdentifier("orders-clear")
            }
            .font(Typography.hint)
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, Spacing.xxs)
        }
    }

    /// The length, and what there is room for when the Mac said. A daemon that names no cap costs
    /// this the second half of the sentence and nothing else.
    private var spent: String {
        guard let limit = orders.limit else { return "\(orders.text.count) characters, every message" }
        return "\(orders.text.count) of \(limit) characters, every message"
    }

    private func load() async {
        guard !asked, let client = model.settings.client() else { return }
        asked = true
        await model.run { orders = try await client.orders(of: session.sessionId) }
    }

    /// What comes back is what was *stored*: the Mac strips anything a terminal would act on and
    /// clamps what is too long, so the pane follows the Mac rather than what was just typed.
    private func keep(_ text: String) async {
        guard let client = model.settings.client() else { return }
        await model.run { orders = try await client.saveOrders(text, of: session.sessionId) }
    }
}
