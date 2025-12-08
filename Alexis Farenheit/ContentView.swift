import SwiftUI
import MapKit
import UIKit

/// Main content view for the Temperature Converter app.
/// Displays current temperature, manual conversion slider, and city search.
struct ContentView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(hex: "1C1C1E")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    TemperatureDisplayView(
                        cityName: viewModel.selectedCity,
                        fahrenheit: viewModel.displayFahrenheit,
                        countryCode: viewModel.selectedCountry
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)

                    ConversionSliderView(fahrenheit: $viewModel.manualFahrenheit)

                    CitySearchView(searchText: $viewModel.searchText) { completion in
                        viewModel.handleCitySelection(completion)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.top, 4)
                    }

                    HStack(spacing: 12) {
                        Button {
                            viewModel.requestLocation()
                            Task { await viewModel.refreshWeatherIfPossible() }
                        } label: {
                            Label("Actualizar ubicación", systemImage: "arrow.triangle.2.circlepath")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "gear")
                                    .padding(10)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .accessibilityLabel("Abrir Ajustes para habilitar ubicación")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .preferredColorScheme(.dark)
        .task { viewModel.onAppear() }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weather")
                    .font(.largeTitle.bold())
                Text("Conversor F° / C° + búsqueda")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "thermometer.medium")
                .foregroundStyle(.yellow)
        }
        .padding(.top, 8)
    }
}

#Preview {
    ContentView()
}
