import WordPressFlux

class SelfHostedJetpackRemoteInstallViewModel: JetpackRemoteInstallViewModel {
    var onChangeState: ((JetpackRemoteInstallState, JetpackRemoteInstallStateViewData) -> Void)?
    private let store = StoreContainer.shared.jetpackInstall
    private var storeReceipt: Receipt?

    private(set) var state: JetpackRemoteInstallState = .install {
        didSet {
            onChangeState?(state, viewData)
        }
    }

    var viewData: JetpackRemoteInstallStateViewData {
        .init(image: state.image,
              titleText: state.title,
              descriptionText: state.message,
              buttonTitleText: state.buttonTitle,
              hidesMainButton: state == .installing,
              hidesLoadingIndicator: state != .installing,
              hidesSupportButton: {
                  switch state {
                  case .failure:
                      return false
                  default:
                      return true
                  }
              }())
    }

    func viewReady() {
        state = .install

        storeReceipt = store.onStateChange { [weak self] (_, state) in
            switch state.current {
            case .loading:
                self?.state = .installing
            case .success:
                self?.state = .success
            case .failure(let error):
                self?.state = .failure(error)
            default:
                break
            }
        }
    }

    func installJetpack(for blog: Blog, isRetry: Bool = false) {
        guard let url = blog.url,
              let username = blog.username,
              let password = blog.password else {
            return
        }

        track(isRetry ? .retry : .start)
        store.onDispatch(JetpackInstallAction.install(url: url, username: username, password: password))
    }

    func track(_ event: JetpackRemoteInstallEvent) {
        switch event {
        case .start:
            WPAnalytics.track(.installJetpackRemoteStart)
        case .completed:
            WPAnalytics.track(.installJetpackRemoteCompleted)
        case .failed(let description, let siteURLString):
            WPAnalytics.track(.installJetpackRemoteFailed,
                              withProperties: ["error_type": description, "site_url": siteURLString])
        case .retry:
            WPAnalytics.track(.installJetpackRemoteRetry)
        case .connect:
            WPAnalytics.track(.installJetpackRemoteConnect)
        case .login:
            WPAnalytics.track(.installJetpackRemoteLogin)
        default:
            break
        }
    }
}
