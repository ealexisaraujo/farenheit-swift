import SwiftUI

// MARK: - Onboarding Page Definition

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome = 0
    case location = 1
    case widget = 2
    case ready = 3

    var id: Int { rawValue }

    var animationName: String {
        switch self {
        case .welcome: return "onboarding-thermometer"
        case .location: return "onboarding-location"
        case .widget: return "onboarding-widget"
        case .ready: return "onboarding-success"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: return "onboarding.page1.title"
        case .location: return "onboarding.page2.title"
        case .widget: return "onboarding.page3.title"
        case .ready: return "onboarding.page4.title"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .welcome: return "onboarding.page1.subtitle"
        case .location: return "onboarding.page2.subtitle"
        case .widget: return "onboarding.page3.subtitle"
        case .ready: return "onboarding.page4.subtitle"
        }
    }

    var buttonTitle: LocalizedStringKey? {
        switch self {
        case .welcome: return nil
        case .location: return "onboarding.page2.button"
        case .widget: return nil
        case .ready: return "onboarding.page4.button"
        }
    }

    var accentColor: Color {
        switch self {
        case .welcome: return Color(hex: "FF6B6B") // Warm coral for thermometer
        case .location: return Color(hex: "4CC9F0") // Sky blue for location
        case .widget: return Color(hex: "7B61FF") // Purple for widget
        case .ready: return Color(hex: "33C759") // Green for success
        }
    }

    var shouldLoopAnimation: Bool {
        switch self {
        case .welcome, .location, .widget: return true
        case .ready: return false // One-shot celebration
        }
    }

    var hasPermissionAction: Bool {
        self == .location
    }

    var isFinalPage: Bool {
        self == .ready
    }
}

// MARK: - Walkthrough Step Definition

enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case todaySnapshot = 0
    case quickActions = 1
    case myCities = 2
    case tools = 3

    var id: Int { rawValue }

    var animationName: String {
        switch self {
        case .todaySnapshot: return "walkthrough-tap"
        case .quickActions: return "walkthrough-tap"
        case .myCities: return "walkthrough-swipe"
        case .tools: return "walkthrough-expand"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .todaySnapshot: return "walkthrough.step1.title"
        case .quickActions: return "walkthrough.step2.title"
        case .myCities: return "walkthrough.step3.title"
        case .tools: return "walkthrough.step4.title"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .todaySnapshot: return "walkthrough.step1.message"
        case .quickActions: return "walkthrough.step2.message"
        case .myCities: return "walkthrough.step3.message"
        case .tools: return "walkthrough.step4.message"
        }
    }

    var accentColor: Color {
        switch self {
        case .todaySnapshot: return .cyan
        case .quickActions: return .blue
        case .myCities: return .indigo
        case .tools: return .teal
        }
    }

    var target: HomeWalkthroughTarget {
        switch self {
        case .todaySnapshot: return .todaySnapshot
        case .quickActions: return .quickActions
        case .myCities: return .myCities
        case .tools: return .tools
        }
    }
}

// MARK: - Onboarding Configuration

struct OnboardingConfiguration {
    static let shared = OnboardingConfiguration()

    /// Animation duration for page transitions
    let pageTransitionDuration: Double = 0.4

    /// Spring animation settings
    let springResponse: Double = 0.5
    let springDamping: Double = 0.8

    /// Animation view size
    let animationSize: CGFloat = 200

    /// Card padding
    let cardPadding: CGFloat = 24

    /// Page indicator size
    let indicatorActiveWidth: CGFloat = 28
    let indicatorInactiveWidth: CGFloat = 8
    let indicatorHeight: CGFloat = 8

    private init() {}
}

// MARK: - Localization Keys (for reference)

/*
 English (en):
 - onboarding.page1.title = "Feel Every Degree"
 - onboarding.page1.subtitle = "Your weather, beautifully converted"
 - onboarding.page2.title = "Weather Follows You"
 - onboarding.page2.subtitle = "Automatic updates wherever you are"
 - onboarding.page2.button = "Enable Location"
 - onboarding.page3.title = "Glanceable from Home Screen"
 - onboarding.page3.subtitle = "Add our widget for instant weather"
 - onboarding.page4.title = "You're All Set!"
 - onboarding.page4.subtitle = "Enjoy temperature clarity"
 - onboarding.page4.button = "Start Using Alexis"
 - onboarding.skip = "Skip"

 - walkthrough.step1.title = "Today Snapshot"
 - walkthrough.step1.message = "Your instant weather at a glance"
 - walkthrough.step2.title = "Quick Actions"
 - walkthrough.step2.message = "Refresh, add cities, check time"
 - walkthrough.step3.title = "My Cities"
 - walkthrough.step3.message = "Swipe to manage your locations"
 - walkthrough.step4.title = "Tools Panel"
 - walkthrough.step4.message = "World time & converter live here"
 - walkthrough.next = "Next"
 - walkthrough.done = "Done"
 - walkthrough.skip = "Skip"

 Portuguese (pt-BR):
 - onboarding.page1.title = "Sinta Cada Grau"
 - onboarding.page1.subtitle = "Seu clima, convertido com beleza"
 - onboarding.page2.title = "O Clima Te Segue"
 - onboarding.page2.subtitle = "Atualizações automáticas onde você estiver"
 - onboarding.page2.button = "Ativar Localização"
 - onboarding.page3.title = "Visível na Tela Inicial"
 - onboarding.page3.subtitle = "Adicione nosso widget para clima instantâneo"
 - onboarding.page4.title = "Tudo Pronto!"
 - onboarding.page4.subtitle = "Aproveite a clareza da temperatura"
 - onboarding.page4.button = "Começar a Usar Alexis"
 - onboarding.skip = "Pular"

 - walkthrough.step1.title = "Snapshot de Hoje"
 - walkthrough.step1.message = "Seu clima instantâneo em um olhar"
 - walkthrough.step2.title = "Ações Rápidas"
 - walkthrough.step2.message = "Atualizar, adicionar cidades, ver hora"
 - walkthrough.step3.title = "Minhas Cidades"
 - walkthrough.step3.message = "Deslize para gerenciar seus locais"
 - walkthrough.step4.title = "Painel de Ferramentas"
 - walkthrough.step4.message = "Hora mundial e conversor ficam aqui"
 - walkthrough.next = "Próximo"
 - walkthrough.done = "Concluído"
 - walkthrough.skip = "Pular"
 */
