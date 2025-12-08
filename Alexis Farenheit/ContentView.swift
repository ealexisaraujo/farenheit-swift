import SwiftUI
import MapKit
import UIKit

/// Main content view for the Temperature Converter app.
/// Displays current temperature, manual conversion slider, and city search.
struct ContentView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color(hex: "1C1C1E")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    header

                    // Main temperature card
                    TemperatureDisplayView(
                        cityName: viewModel.selectedCity,
                        fahrenheit: viewModel.displayFahrenheit,
                        countryCode: viewModel.selectedCountry
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)

                    // Conversion slider
                    ConversionSliderView(fahrenheit: $viewModel.manualFahrenheit)

                    // City search button - opens sheet
                    CitySearchButton(currentCity: viewModel.selectedCity) { completion in
                        viewModel.handleCitySelection(completion)
                    }

                    // Error message
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .preferredColorScheme(.dark)
        .task { viewModel.onAppear() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weather")
                    .font(.largeTitle.bold())
                Text("Conversor F° / C°")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Loading indicator
            if viewModel.isLoadingWeather {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "thermometer.medium")
                    .font(.title2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.top, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Refresh location button
            Button {
                viewModel.requestLocation()
                Task { await viewModel.refreshWeatherIfPossible() }
            } label: {
                Label("Actualizar", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(viewModel.isLoadingWeather)

            // Settings button (if location denied)
            if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.title3)
                        .padding(12)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel("Abrir Ajustes")
            }
        }
    }
}

#Preview {
    ContentView()
}
