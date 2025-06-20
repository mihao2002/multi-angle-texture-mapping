import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = Coordinator()

    var body: some View {
        VStack {
            ARViewContainer(coordinator: coordinator)
                .edgesIgnoringSafeArea(.all)

            FurnitureListView(furnitureCandidates: coordinator.furnitureCandidates)
                .frame(height: 200)
                .background(Color(UIColor.systemBackground))
        }
    }
}
