import XCTest
@testable import Library
@testable import KsApi
@testable import ReactiveExtensions_TestHelpers
import Result
import KsApi
import PassKit
import Prelude

private let questionMark = CharacterSet(charactersIn: "?")

final class CheckoutViewModelTests: TestCase {
  fileprivate let vm: CheckoutViewModelType = CheckoutViewModel()

  fileprivate let closeLoginTout = TestObserver<(), NoError>()
  fileprivate let dismissViewController = TestObserver<(), NoError>()
  fileprivate let evaluateJavascript = TestObserver<String, NoError>()
  fileprivate let goToPaymentAuthorization = TestObserver<NSDictionary, NoError>()
  fileprivate let goToSafariBrowser = TestObserver<URL, NoError>()
  fileprivate let goToThanks = TestObserver<Project, NoError>()
  fileprivate let goToWebModal = TestObserver<URLRequest, NoError>()
  fileprivate let openLoginTout = TestObserver<(), NoError>()
  fileprivate let popViewController = TestObserver<(), NoError>()
  fileprivate let setStripeAppleMerchantIdentifier = TestObserver<String, NoError>()
  fileprivate let setStripePublishableKey = TestObserver<String, NoError>()
  fileprivate let showAlert = TestObserver<String, NoError>()
  fileprivate let webViewLoadRequestIsPrepared = TestObserver<Bool, NoError>()
  fileprivate let webViewLoadRequestURL = TestObserver<String, NoError>()

  override func setUp() {
    super.setUp()

    self.vm.outputs.closeLoginTout.observe(self.closeLoginTout.observer)
    self.vm.outputs.dismissViewController.observe(self.dismissViewController.observer)
    self.vm.outputs.evaluateJavascript.observe(self.evaluateJavascript.observer)
    self.vm.outputs.goToPaymentAuthorization.map { $0.encode() as NSDictionary }
      .observe(self.goToPaymentAuthorization.observer)
    self.vm.outputs.goToSafariBrowser.observe(self.goToSafariBrowser.observer)
    self.vm.outputs.goToThanks.observe(self.goToThanks.observer)
    self.vm.outputs.goToWebModal.observe(self.goToWebModal.observer)
    self.vm.outputs.openLoginTout.observe(self.openLoginTout.observer)
    self.vm.outputs.popViewController.observe(self.popViewController.observer)
    self.vm.outputs.setStripeAppleMerchantIdentifier.observe(self.setStripeAppleMerchantIdentifier.observer)
    self.vm.outputs.setStripePublishableKey.observe(self.setStripePublishableKey.observer)
    self.vm.outputs.showAlert.observe(self.showAlert.observer)
    self.vm.outputs.webViewLoadRequest
      .map { AppEnvironment.current.apiService.isPrepared(request: $0) }
      .observe(self.webViewLoadRequestIsPrepared.observer)
    self.vm.outputs.webViewLoadRequest
      .map { request -> String? in
        // Trim query parameters
        guard let url = request.URL else { return nil }
        guard let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = components.queryItems?.filter {
          $0.name != "client_id" && $0.name != "oauth_token"
        }
        return components.string?.stringByTrimmingCharactersInSet(questionMark)
      }
      .ignoreNil()
      .observe(self.webViewLoadRequestURL.observer)
  }

  func testCancelButtonPopsViewController() {
    let project = Project.template

    self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                 project: project,
                                 reward: .template,
                                 applePayCapable: false)
    self.vm.inputs.viewDidLoad()

    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 1: Cancel button tapped
    self.popViewController.assertDidNotEmitValue()
    XCTAssertEqual([], self.trackingClient.events)

    self.vm.inputs.cancelButtonTapped()
    self.popViewController.assertValueCount(1)
    XCTAssertEqual(["Checkout Cancel", "Canceled Checkout"],
                   self.trackingClient.events, "Cancel event and its deprecated version are tracked")
    XCTAssertEqual(["new_pledge", "new_pledge"],
                   self.trackingClient.properties(forKey: "pledge_context", as: String.self))
  }

  func testNewPledgeRequestDismissesViewController() {
    let project = Project.template

    self.webViewLoadRequestURL.assertDidNotEmitValue()

    // 1: Open new payments form
    self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                 project: project,
                                 reward: .template,
                                 applePayCapable: false)
    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
      "Not prepared"
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPaymentsRequest().prepared(),
        navigationType: .Other)
    )

    self.webViewLoadRequestIsPrepared.assertValues([true, true])
    self.webViewLoadRequestURL.assertValues(
      [newPaymentsURL(), newPaymentsURL()]
    )

    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 2: Web view should not attempt to load the new pledge request
    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )

    self.webViewLoadRequestURL.assertValues([newPaymentsURL(), newPaymentsURL()])

    // 3: If we requested new pledge, the view controller should be dismissed
    self.dismissViewController.assertValueCount(1)
  }

  func testCancelPledge() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(initialRequest: editPledgeRequest(project: project).prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([editPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: editPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Click cancel link
      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: cancelPledgeRequest(project: project),
          navigationType: .LinkClicked
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), cancelPledgeURL(project: project)]
      )
      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: cancelPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 3: Confirm cancellation
      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )
      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), cancelPledgeURL(project: project), pledgeURL(project: project)]
      )

      // 4: Redirect to project, view controller dismissed
      self.dismissViewController.assertDidNotEmitValue()
      XCTAssertEqual([], self.trackingClient.events)
      XCTAssertEqual([], self.trackingClient.properties(forKey: "type", as: String.self))

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: projectRequest(project: project), navigationType: .Other)
      )
      XCTAssertEqual(["Checkout Cancel", "Canceled Checkout"],
                     self.trackingClient.events)
      self.dismissViewController.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testChangePaymentMethod() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(initialRequest: editPledgeRequest(project: project).prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([editPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: editPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Click change payment method button
      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: changePaymentMethodRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), changePaymentMethodURL(project: project)]
      )
      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: changePaymentMethodRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 3: Redirect to new payments form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), changePaymentMethodURL(project: project), newPaymentsURL()]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 4: Pledge with new card
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          editPledgeURL(project: project),
          changePaymentMethodURL(project: project),
          newPaymentsURL(),
          paymentsURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest().prepared(), navigationType: .Other)
      )

      // 5: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(4)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(
            project: project, racing: false),
          navigationType: .Other
        ),
        "Not prepared"
      )
      self.goToThanks.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testLoggedInUserPledgingWithNewCard() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      // 1: Open new payments form
      self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPaymentsRequest().prepared(),
          navigationType: .Other)
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPaymentsURL(), newPaymentsURL()]
      )

      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Pledge with new card
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPaymentsURL(),
          newPaymentsURL(),
          paymentsURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest().prepared(), navigationType: .Other)
      )

      // 3: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Don't go to the URL since we handle it with a native thanks screen."
      )
      self.goToThanks.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testLoggedInUserPledgingWithStoredCard() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      // 1: Open new payments form
      self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPaymentsRequest().prepared(),
          navigationType: .Other)
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPaymentsURL(), newPaymentsURL()]
      )

      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Pledge with stored card
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPaymentsURL(),
          newPaymentsURL(),
          useStoredCardURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest().prepared(), navigationType: .Other)
      )

      // 3: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Don't go to the URL since we handle it with a native thanks screen."
      )
      self.goToThanks.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testLoginDuringCheckout() {
    let project = Project.template

    self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                 project: project,
                                 reward: .template,
                                 applePayCapable: false)
    self.vm.inputs.viewDidLoad()

    // 1: Show reward and shipping form
    self.webViewLoadRequestIsPrepared.assertValues([true])
    self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPaymentsRequest().prepared(),
        navigationType: .Other
      )
    )
    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 2: Submit reward and shipping form
    self.webViewLoadRequestURL.assertValueCount(1)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(
        withRequest: pledgeRequest(project: project),
        navigationType: .FormSubmitted
      ),
      "Not prepared"
    )

    self.webViewLoadRequestIsPrepared.assertValues([true, true])
    self.webViewLoadRequestURL.assertValues(
      [newPaymentsURL(), pledgeURL(project: project)]
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: pledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )

    // 3: Interrupt checkout for login/signup
    self.openLoginTout.assertDidNotEmitValue()

    XCTAssertFalse(self.vm.inputs.shouldStartLoad(withRequest: signupRequest(), navigationType: .Other))
    self.openLoginTout.assertValueCount(1)

    // 4: Login
    AppEnvironment.login(.init(accessToken: "deadbeef", user: User.template))
    self.closeLoginTout.assertDidNotEmitValue()

    self.vm.inputs.userSessionStarted()
    self.closeLoginTout.assertValueCount(1)

    // 5: Attempt pledge request again
    self.webViewLoadRequestURL.assertValues(
      [newPaymentsURL(), pledgeURL(project: project), pledgeURL(project: project)],
      "Attempt pledge request again, now that user is logged in"
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: pledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )
    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
      "Not prepared"
    )

    self.webViewLoadRequestURL.assertValues(
      [
        newPaymentsURL(),
        pledgeURL(project: project),
        pledgeURL(project: project),
        newPaymentsURL()
      ]
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
    )

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")

    // The rest of the checkout flow is the same as if the user had been logged in at the beginning,
    // so no need for further tests.
  }

  func testManagePledge() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(initialRequest: editPledgeRequest(project: project).prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([editPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: editPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Submit reward and shipping form
      self.webViewLoadRequestURL.assertValueCount(1)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), pledgeURL(project: project)]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )

      // 3: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Don't go to the URL since we handle it with a native thanks screen."
      )
      self.goToThanks.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testModalRequests() {
    let project = Project.template
    self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                 project: project,
                                 reward: .template,
                                 applePayCapable: false)
    self.vm.inputs.viewDidLoad()

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(),
        navigationType: .Other)
    )
    self.goToWebModal.assertValueCount(0)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: creatorRequest(project: project),
        navigationType: .LinkClicked)
    )
    self.goToSafariBrowser.assertValueCount(0)
    self.goToWebModal.assertValueCount(1)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: privacyPolicyRequest(project: project),
        navigationType: .LinkClicked)
    )
    self.goToSafariBrowser.assertValueCount(1)
    self.goToWebModal.assertValueCount(1)
  }

  func testRacingFailure() {
    let failedEnvelope = CheckoutEnvelope.failed
    let project = Project.template
    withEnvironment(apiService: MockService(fetchCheckoutResponse: failedEnvelope), currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      // 1: Open new payments form
      self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPaymentsRequest().prepared(),
          navigationType: .Other)
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPaymentsURL(), newPaymentsURL()]
      )

      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Pledge with stored card
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPaymentsURL(),
          newPaymentsURL(),
          useStoredCardURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest().prepared(), navigationType: .Other)
      )

      // 3: Checkout is racing, delay a second to check status (failed!), then display failure alert.
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: true),
          navigationType: .Other
        )
      )
      self.showAlert.assertValueCount(0)

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertValueCount(0)
      self.showAlert.assertValues([failedEnvelope.stateReason])

      // 4: Alert dismissed, pop view controller
      self.popViewController.assertValueCount(0)

      self.vm.inputs.failureAlertButtonTapped()
      self.popViewController.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testRacingSuccess() {
    let envelope = CheckoutEnvelope.successful
    let project = Project.template
    withEnvironment(apiService: MockService(fetchCheckoutResponse: envelope), currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      // 1: Open new payments form
      self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPaymentsRequest().prepared(),
          navigationType: .Other)
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPaymentsURL(), newPaymentsURL()]
      )

      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Pledge with stored card
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPaymentsURL(),
          newPaymentsURL(),
          useStoredCardURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest().prepared(), navigationType: .Other)
      )

      // 3: Checkout is racing, delay a second to check status (successful!), then go to thanks.
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: true),
          navigationType: .Other
        )
      )

      self.scheduler.advanceByInterval(1)
      self.showAlert.assertValueCount(0)
      self.goToThanks.assertValueCount(1)
    }

    self.evaluateJavascript.assertValueCount(0, "No javascript was evaluated.")
  }

  func testProjectRequestDismissesViewController() {
    let project = Project.template

    self.webViewLoadRequestURL.assertDidNotEmitValue()

    // 1: Open new payments form
    self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                 project: project,
                                 reward: .template,
                                 applePayCapable: false)
    self.vm.inputs.viewDidLoad()

    self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
      "Not prepared"
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPaymentsRequest().prepared(),
        navigationType: .Other)
    )

    self.webViewLoadRequestIsPrepared.assertValues([true, true])
    self.webViewLoadRequestURL.assertValues(
      [newPaymentsURL(), newPaymentsURL()]
    )

    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 2: Project link clicked
    self.dismissViewController.assertDidNotEmitValue()
    XCTAssertEqual([], self.trackingClient.events)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(
        withRequest: projectRequest(project: project),
        navigationType: .LinkClicked
      )
    )

    self.dismissViewController.assertValueCount(1)
    XCTAssertEqual(["Checkout Cancel", "Canceled Checkout"],
                   self.trackingClient.events, "Cancel event and its deprecated version are tracked")
  }

  func testEmbeddedApplePayFlow() {
    let amount = 25
    let location = Location.template
    let reward = .template
      |> Reward.lens.minimum .~ 20
    let project = .template
      |> Project.lens.rewards .~ [reward]

    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      // 1: Open new payments form
      self.vm.inputs.configureWith(initialRequest: newPaymentsRequest().prepared(),
                                   project: project,
                                   reward: .template,
                                   applePayCapable: true)
      self.vm.inputs.viewDidLoad()

      self.webViewLoadRequestURL.assertValues([newPaymentsURL()])

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPaymentsRequest().prepared(),
          navigationType: .Other)
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPaymentsURL(), newPaymentsURL()]
      )

      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Pledge with apple pay
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: applePayUrlRequest(
            project: project,
            amount: amount,
            reward: reward,
            location: location
          ),
          navigationType: .LinkClicked
        ),
        "Apple Pay url not allowed"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPaymentsURL(),
          newPaymentsURL()
        ]
      )

      // 3: Apple Pay sheet

      self.goToPaymentAuthorization.assertValueCount(1)

      self.vm.inputs.paymentAuthorizationWillAuthorizePayment()

      XCTAssertEqual(["Apple Pay Show Sheet", "Showed Apple Pay Sheet"], self.trackingClient.events)

      self.vm.inputs.paymentAuthorization(
        didAuthorizePayment: .init(
          tokenData: .init(
            paymentMethodData: .init(displayName: "AmEx 1111", network: "AmEx", type: .Credit),
            transactionIdentifier: "apple_pay_deadbeef"
          )
        )
      )

      XCTAssertEqual(
        ["Apple Pay Show Sheet", "Showed Apple Pay Sheet", "Apple Pay Authorized", "Authorized Apple Pay"],
        self.trackingClient.events)

      self.vm.inputs.stripeCreatedToken(stripeToken: "stripe_deadbeef", error: nil)

      XCTAssertEqual(
        ["Apple Pay Show Sheet", "Showed Apple Pay Sheet", "Apple Pay Authorized", "Authorized Apple Pay",
          "Apple Pay Stripe Token Created", "Created Apple Pay Stripe Token"],
        self.trackingClient.events)

      self.vm.inputs.paymentAuthorizationDidFinish()

      XCTAssertEqual(
        ["Apple Pay Show Sheet", "Showed Apple Pay Sheet", "Apple Pay Authorized", "Authorized Apple Pay",
          "Apple Pay Stripe Token Created", "Created Apple Pay Stripe Token", "Apple Pay Finished"],
        self.trackingClient.events
      )

      XCTAssertEqual(
        ["new_pledge", "new_pledge", "new_pledge", "new_pledge", "new_pledge", "new_pledge", "new_pledge"],
        self.trackingClient.properties(forKey: "pledge_context", as: String.self)
      )

      self.evaluateJavascript.assertValues([
        "window.checkout_apple_pay_next({\"apple_pay_token\":{\"transaction_identifier\":" +
          "\"apple_pay_deadbeef\",\"payment_instrument_name\":\"AmEx 1111\",\"payment_network\":\"AmEx\"}," +
        "\"stripe_token\":{\"id\":\"stripe_deadbeef\"}});"
        ])

      // 4: Submit payment form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPaymentsURL(),
          newPaymentsURL(),
          paymentsURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest().prepared(), navigationType: .Other)
      )
      XCTAssertEqual(
        ["Apple Pay Show Sheet", "Showed Apple Pay Sheet", "Apple Pay Authorized", "Authorized Apple Pay",
          "Apple Pay Stripe Token Created", "Created Apple Pay Stripe Token", "Apple Pay Finished",
        ],
        self.trackingClient.events
      )

      // 5: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Don't go to the URL since we handle it with a native thanks screen."
      )
      self.goToThanks.assertValueCount(1)
    }
  }

  func testSetStripeAppleMerchantIdentifier_NotApplePayCapable() {
    self.vm.inputs.configureWith(initialRequest: newPledgeRequest(project: .template).prepared(),
                                 project: .template,
                                 reward: .template,
                                 applePayCapable: false)
    self.vm.inputs.viewDidLoad()

    self.setStripeAppleMerchantIdentifier.assertValues([])
  }

  func testSetStripeAppleMerchantIdentifier_ApplePayCapable() {
    self.vm.inputs.configureWith(initialRequest: newPledgeRequest(project: .template).prepared(),
                                 project: .template,
                                 reward: .template,
                                 applePayCapable: true)
    self.vm.inputs.viewDidLoad()

    self.setStripeAppleMerchantIdentifier.assertValues(
      [PKPaymentAuthorizationViewController.merchantIdentifier]
    )
  }

  func testSetStripePublishableKey_NotApplePayCapable() {
    withEnvironment(config: .template |> Config.lens.stripePublishableKey .~ "deadbeef") {
      self.vm.inputs.configureWith(initialRequest: newPledgeRequest(project: .template).prepared(),
                                   project: .template,
                                   reward: .template,
                                   applePayCapable: false)
      self.vm.inputs.viewDidLoad()

      self.setStripePublishableKey.assertValues([])
    }
  }

  func testSetStripePublishableKey_ApplePayCapable() {
    withEnvironment(config: .template |> Config.lens.stripePublishableKey .~ "deadbeef") {
      self.vm.inputs.configureWith(initialRequest: newPledgeRequest(project: .template).prepared(),
                                   project: .template,
                                   reward: .template,
                                   applePayCapable: true)
      self.vm.inputs.viewDidLoad()

      self.setStripePublishableKey.assertValues(["deadbeef"])
    }
  }

}

internal extension URLRequest {
  internal func prepared() -> URLRequest {
    return AppEnvironment.current.apiService.preparedRequest(forRequest: self)
  }
}

private func applePayUrlRequest(project: Project,
                                        amount: Int,
                                        reward: Reward,
                                        location: Location) -> URLRequest {

  let payload = [
    "country_code": project.country.countryCode,
    "currency_code": project.country.currencyCode,
    "merchant_identifier": PKPaymentAuthorizationViewController.merchantIdentifier,
    "supported_networks": [ "AmEx", "Visa", "MasterCard", "Discover" ],
    "payment_summary_items": [
      [
        "label": project.name,
        "amount": "\(amount)"
      ],
      [
        "label": "Kickstarter (if funded)",
        "amount": "\(amount)"
      ]
    ]
  ]

  return (try? JSONSerialization.dataWithJSONObject(payload, options: []))
    .flatMap { String(data: $0.base64EncodedDataWithOptions([]), encoding: NSUTF8StringEncoding) }
    .map { "https://www.kickstarter.com/checkouts/1/payments/apple-pay?payload=\($0)" }
    .flatMap(NSURL.init(string:))
    .flatMap(NSURLRequest.init(URL:))
    .coalesceWith(NSURLRequest())
}

private func cancelPledgeRequest(project: Project) -> URLRequest {
  return NSURLRequest(url: NSURL(string: cancelPledgeURL(project: project))! as URL) as URLRequest
}

private func cancelPledgeURL(project: Project) -> String {
  return "\(project.urls.web.project)/pledge/destroy"
}

private func changePaymentMethodRequest(project: Project) -> URLRequest {
  return NSURLRequest(url: NSURL(string: changePaymentMethodURL(project: project))! as URL) as URLRequest
}

private func changePaymentMethodURL(project: Project) -> String {
  return "\(project.urls.web.project)/pledge/change_method"
}

private func creatorRequest(project: Project) -> URLRequest {
  return NSURLRequest(url: NSURL(string: creatorURL(project: project))! as URL) as URLRequest
}

private func creatorURL(project: Project) -> String {
  return "\(project.urls.web.project)/pledge/big_print?modal=true#creator"
}

private func editPledgeRequest(project: Project) -> URLRequest {
  return NSURLRequest(url: NSURL(string: editPledgeURL(project: project))! as URL) as URLRequest
}

private func editPledgeURL(project: Project) -> String {
  return "\(project.urls.web.project)/pledge/edit"
}

private func newPaymentsRequest() -> URLRequest {
  return URLRequest(url: URL(string: newPaymentsURL())!)
}

private func newPaymentsURL() -> String {
  return "https://www.kickstarter.com/checkouts/1/payments/new"
}

private func newPledgeRequest(project: Project) -> URLRequest {
  return NSURLRequest(url: NSURL(string: newPledgeURL(project: project))! as URL) as URLRequest
}

private func newPledgeURL(project: Project) -> String {
  return "\(project.urls.web.project)/pledge/new"
}

private func paymentsRequest() -> URLRequest {
  let request = NSMutableURLRequest(url: URL(string: paymentsURL())!)
  request.httpMethod = "POST"
  return request as URLRequest
}

private func paymentsURL() -> String {
  return "https://www.kickstarter.com/checkouts/1/payments"
}

private func pledgeRequest(project: Project) -> URLRequest {
  let request = NSMutableURLRequest(url: URL(string: pledgeURL(project: project))!)
  request.httpMethod = "POST"
  return request as URLRequest
}

private func pledgeURL(project: Project) -> String {
  return "\(project.urls.web.project)/pledge"
}

private func privacyPolicyRequest(project: Project) -> URLRequest {
  return NSURLRequest(url:
    NSURL(string: privacyPolicyURL(project: project))! as URL
  ) as URLRequest
}

private func privacyPolicyURL(project: Project) -> String {
  return "\(project.urls.web.project)/privacy?modal=true&ref=checkout_payment_sources_page"
}

private func projectRequest(project: Project) -> URLRequest {
  return NSURLRequest(url: NSURL(string: project.urls.web.project)! as URL) as URLRequest
}

private func signupRequest() -> URLRequest {
  return URLRequest(url: URL(string: "https://www.kickstarter.com/signup?context=checkout&then=%2Ffoo")!)
}

private func stripeRequest() -> URLRequest {
  return URLRequest(url: URL(string: stripeURL())!)
}

private func stripeURL() -> String {
  return "https://js.stripe.com/v2/channel.html"
}

private func thanksRequest(project: Project, racing: Bool) -> URLRequest {
  return NSURLRequest(url: NSURL(string: thanksURL(project: project, racing: racing))! as URL) as URLRequest
}

private func thanksURL(project: Project, racing: Bool) -> String {
  return "\(project.urls.web.project)/checkouts/1/thanks\(racing ? "?racing=1" : "")"
}

private func useStoredCardRequest() -> URLRequest {
  return URLRequest(url: URL(string: useStoredCardURL())!)
}

private func useStoredCardURL() -> String {
  return "https://www.kickstarter.com/checkouts/1/payments/use_stored_card"
}
