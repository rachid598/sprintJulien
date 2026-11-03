import SwiftUI
import SwiftData
import SprintTimerCore

private struct ActiveRace: Identifiable {
    var id: UUID { race.id }
    var race: RaceDocument
    var reopening: Bool
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredRace.date, order: .reverse) private var races: [StoredRace]
    @State private var creating = false
    @State private var guide = false
    @State private var active: ActiveRace?
    @State private var pendingRace: RaceDocument?
    @State private var problem: String?
    @State private var deleting: StoredRace?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("CHAQUE ARRIVÉE COMPTE", systemImage: "flag.checkered")
                            .font(.caption.weight(.bold)).foregroundStyle(.orange)
                        Text("La ligne.\nL’instant. Le résultat.").font(.largeTitle.bold())
                        Text("Chronométrez votre groupe, analysez les arrivées et gardez les résultats sur cet appareil.")
                            .foregroundStyle(.secondary)
                        Button { creating = true } label: {
                            Label("Nouvelle course", systemImage: "plus.circle.fill").font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("race.create")
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.orange.opacity(0.06))
                Section("Historique · \(races.count) course(s)") {
                    if races.isEmpty {
                        ContentUnavailableView("La piste est à vous", systemImage: "figure.run",
                            description: Text("Créez votre première course. Les courses et les images sont sauvegardées localement."))
                    }
                    ForEach(races) { stored in
                        Button {
                            do { active = ActiveRace(race: try PersistenceService(context: context).recover(stored), reopening: true) }
                            catch { problem = error.localizedDescription }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "flag.checkered").font(.title2).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stored.name).font(.headline).foregroundStyle(.primary)
                                    Text(stored.date, format: .dateTime.day().month().year().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.swipeActions { Button("Supprimer", role: .destructive) { deleting = stored } }
                    }
                }
            }
            .navigationTitle("SprintTimer")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Guide", systemImage: "questionmark.circle") { guide = true } } }
            .sheet(isPresented: $creating, onDismiss: {
                if let pendingRace {
                    active = ActiveRace(race: pendingRace, reopening: false)
                    self.pendingRace = nil
                }
            }) {
                NewRaceView { document in
                    pendingRace = document
                    creating = false
                }
            }
            .sheet(isPresented: $guide) { GuideView() }
            .fullScreenCover(item: $active) { item in
                NavigationStack { RaceView(race: item.race, context: context, reopening: item.reopening) }
            }
            .alert("Impossible d’ouvrir la course", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Fermer", role: .cancel) { problem = nil }
            } message: { Text(problem ?? "") }
            .confirmationDialog("Supprimer cette course et ses médias ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Supprimer définitivement", role: .destructive) {
                    if let deleting {
                        do { try PersistenceService(context: context).delete(deleting) } catch { problem = error.localizedDescription }
                    }
                    deleting = nil
                }
            }
        }
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("1 · Préparer") {
                    Text("Choisissez le mode et les participants. Placez l’iPhone en portrait sur un support stable, dans l’alignement de la ligne d’arrivée. Cadrez tous les couloirs.")
                    Text("La ligne orange définit la bande extraite. Réglez sa position avant le départ. Utilisez un bon éclairage pour les hautes fréquences.")
                }
                Section("2 · Chronométrer") {
                    Text("Démarrez le chronomètre, puis appuyez sur Capturer les arrivées lorsque les concurrents approchent. Le temps de course et le début de la capture sont indépendants.")
                    Text("Gardez l’application au premier plan. L’arrière-plan, un appel ou le verrouillage peuvent interrompre la caméra. La durée maximale arrête la capture automatiquement.")
                }
                Section("3 · Analyser") {
                    Text("Faites défiler la photo horizontalement, touchez une bande ou utilisez les flèches. Le curseur affiche l’horodatage réel de l’image choisie. Sélectionnez un participant puis Marquer ce temps.")
                    Text("En vidéo, les flèches sélectionnent les images réellement enregistrées. Une différence de temps importante entre deux images révèle une lacune ; elle n’est pas interpolée.")
                }
                Section("Précision et modes automatiques") {
                    Text("L’affichage au centième n’est pas une garantie de précision. Cadence, exposition, rolling shutter, réaction humaine et latence audio doivent être contrôlés sur le terrain.")
                    Text("Instant Finish estime l’entrée d’un mouvement dans une zone autour de la ligne. Des coureurs côte à côte, un fond mobile ou un changement de lumière peuvent provoquer des détections manquées ou supplémentaires. Révisez les résultats dans la vidéo.")
                    Text("Un décalage positif ajoute du temps au résultat en reculant l’origine du départ. Pour un signal entendu à 100 m, le retard acoustique est d’environ 0,29 s (100/343), à calibrer selon les conditions.")
                }
                Section("Confidentialité") {
                    Text("Aucun compte ni service distant n’est requis. Les images, noms et résultats restent sur cet appareil jusqu’à un partage explicite. Exportez vos courses pour les conserver en dehors de l’application.")
                }
            }.navigationTitle("Sur la piste")
                .toolbar { Button("Fermer") { dismiss() } }
        }
    }
}
