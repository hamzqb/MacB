import MacBCore
import SwiftUI

/// What MacB did while you were away.
///
/// The card somebody sees when they sit back down: what was found, in two
/// sentences, and then the things it would like to do about it, each with a
/// yes and a no. Nothing on this card has happened yet — that is the whole
/// point of it — so the buttons are the first moment anything acts.
struct IslandAgentView: View {
    @ObservedObject var jobs: AgentJobStore
    var approve: (AgentProposal, UUID) -> Void
    var refuse: (AgentProposal, UUID) -> Void
    var dismiss: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
            if let job = jobs.waiting.first {
                header(job)
                Text(job.report)
                    .font(.system(size: MacBDesign.TypeScale.body))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                let pending = job.proposals.filter(\.isPending)
                if !pending.isEmpty {
                    VStack(spacing: MacBDesign.Space.tight) {
                        ForEach(pending.prefix(3)) { proposal in
                            proposalRow(proposal, in: job.id)
                        }
                    }
                }
                HStack(spacing: MacBDesign.Space.snug) {
                    Button("Tamam") { dismiss(job.id) }
                        .buttonStyle(IslandCapsuleButtonStyle())
                    if pending.count > 3 {
                        Text("+\(pending.count - 3) daha")
                            .font(.system(size: MacBDesign.TypeScale.micro))
                            .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                .buttonStyle(.plain)
            } else if let job = jobs.running.first {
                header(job)
                Text("Sen dönünce hazır olacak.")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func header(_ job: AgentJob) -> some View {
        HStack(spacing: MacBDesign.Space.close) {
            Image(systemName: job.state.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.accent)
                .frame(width: 22, height: 22)
                .background(MacBDesign.IslandToken.accent.opacity(0.14), in: Circle())
                .symbolEffect(.pulse, isActive: !job.isFinished)
            VStack(alignment: .leading, spacing: 0) {
                Text(job.title)
                    .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                    .lineLimit(1)
                Text(job.state.title)
                    .font(.system(size: MacBDesign.TypeScale.micro))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            }
            Spacer(minLength: 0)
        }
    }

    /// One thing waiting for a yes.
    ///
    /// The text is the same line the live assistant would have shown before
    /// doing it, so approving something prepared in the background reads
    /// exactly like approving something asked for out loud.
    private func proposalRow(_ proposal: AgentProposal, in jobID: UUID) -> some View {
        HStack(spacing: MacBDesign.Space.snug) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            Text(proposal.text)
                .font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: MacBDesign.Space.snug)
            Button("Yok") { refuse(proposal, jobID) }
                .buttonStyle(IslandCapsuleButtonStyle())
            Button("Yap") { approve(proposal, jobID) }
                .buttonStyle(IslandCapsuleButtonStyle(isPrimary: true))
        }
        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, MacBDesign.Space.close)
        .padding(.vertical, MacBDesign.Space.snug)
        .background(MacBDesign.IslandToken.Fill.hairline,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
