import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_am.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('am'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Cofiz'**
  String get appTitle;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @workers.
  ///
  /// In en, this message translates to:
  /// **'Collectors'**
  String get workers;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back,'**
  String get welcomeBack;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @todaysActivity.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Activity'**
  String get todaysActivity;

  /// No description provided for @totalActivity.
  ///
  /// In en, this message translates to:
  /// **'Total Activity'**
  String get totalActivity;

  /// No description provided for @distributed.
  ///
  /// In en, this message translates to:
  /// **'Distributed'**
  String get distributed;

  /// No description provided for @returned.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get returned;

  /// No description provided for @netBalance.
  ///
  /// In en, this message translates to:
  /// **'Net Balance'**
  String get netBalance;

  /// No description provided for @activeWorkers.
  ///
  /// In en, this message translates to:
  /// **'Collectors'**
  String get activeWorkers;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @perf.
  ///
  /// In en, this message translates to:
  /// **'Perf'**
  String get perf;

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get sales;

  /// No description provided for @noWorkersYet.
  ///
  /// In en, this message translates to:
  /// **'No collectors yet'**
  String get noWorkersYet;

  /// No description provided for @addWorkersToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Add collectors to get started'**
  String get addWorkersToGetStarted;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'ETB'**
  String get currency;

  /// No description provided for @searchWorkers.
  ///
  /// In en, this message translates to:
  /// **'Search collectors...'**
  String get searchWorkers;

  /// No description provided for @noWorkersFound.
  ///
  /// In en, this message translates to:
  /// **'No collectors found'**
  String get noWorkersFound;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @twoFactorAuth.
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Authentication'**
  String get twoFactorAuth;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @areYouSureSignOut.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get areYouSureSignOut;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @noDataToExport.
  ///
  /// In en, this message translates to:
  /// **'No data to export'**
  String get noDataToExport;

  /// No description provided for @manageYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Manage your account'**
  String get manageYourAccount;

  /// No description provided for @customizeAlerts.
  ///
  /// In en, this message translates to:
  /// **'Customize alerts'**
  String get customizeAlerts;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @weeklyActivity.
  ///
  /// In en, this message translates to:
  /// **'Weekly Activity'**
  String get weeklyActivity;

  /// No description provided for @aboutCofiz.
  ///
  /// In en, this message translates to:
  /// **'About Cofiz'**
  String get aboutCofiz;

  /// No description provided for @auditLogs.
  ///
  /// In en, this message translates to:
  /// **'Audit Logs'**
  String get auditLogs;

  /// No description provided for @businessSettings.
  ///
  /// In en, this message translates to:
  /// **'Business Settings'**
  String get businessSettings;

  /// No description provided for @businessInformation.
  ///
  /// In en, this message translates to:
  /// **'Business Information'**
  String get businessInformation;

  /// No description provided for @dataManagement.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get dataManagement;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendEmail.
  ///
  /// In en, this message translates to:
  /// **'Send Email'**
  String get sendEmail;

  /// No description provided for @sendSms.
  ///
  /// In en, this message translates to:
  /// **'Send SMS'**
  String get sendSms;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReport;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get loadMore;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @busy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get busy;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @historyDescription.
  ///
  /// In en, this message translates to:
  /// **'View your transaction history'**
  String get historyDescription;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @qty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qty;

  /// No description provided for @avgPrice.
  ///
  /// In en, this message translates to:
  /// **'Avg Price'**
  String get avgPrice;

  /// No description provided for @workerCommission.
  ///
  /// In en, this message translates to:
  /// **'Collector Commission:'**
  String get workerCommission;

  /// No description provided for @commissionEarned.
  ///
  /// In en, this message translates to:
  /// **'Commission Earned'**
  String get commissionEarned;

  /// No description provided for @commissionRate.
  ///
  /// In en, this message translates to:
  /// **'Commission Rate (per Kg)'**
  String get commissionRate;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @currentBalance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get currentBalance;

  /// No description provided for @totalDistributed.
  ///
  /// In en, this message translates to:
  /// **'Total Distributed'**
  String get totalDistributed;

  /// No description provided for @totalReturned.
  ///
  /// In en, this message translates to:
  /// **'Total Returned'**
  String get totalReturned;

  /// No description provided for @coffeePurchased.
  ///
  /// In en, this message translates to:
  /// **'Coffee Purchased'**
  String get coffeePurchased;

  /// No description provided for @totalCoffeePurchased.
  ///
  /// In en, this message translates to:
  /// **'Total Coffee Purchased'**
  String get totalCoffeePurchased;

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactions;

  /// No description provided for @transactionHistory.
  ///
  /// In en, this message translates to:
  /// **'Transaction History'**
  String get transactionHistory;

  /// No description provided for @recentTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get recentTransactions;

  /// No description provided for @jenfel.
  ///
  /// In en, this message translates to:
  /// **'Jenfel'**
  String get jenfel;

  /// No description provided for @yetatebe.
  ///
  /// In en, this message translates to:
  /// **'Yetatebe'**
  String get yetatebe;

  /// No description provided for @special.
  ///
  /// In en, this message translates to:
  /// **'Special'**
  String get special;

  /// No description provided for @coffeeType.
  ///
  /// In en, this message translates to:
  /// **'Coffee Type'**
  String get coffeeType;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @pricePerKg.
  ///
  /// In en, this message translates to:
  /// **'Price/Kg'**
  String get pricePerKg;

  /// No description provided for @weight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weight;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount:'**
  String get totalAmount;

  /// No description provided for @distributeMoney.
  ///
  /// In en, this message translates to:
  /// **'Distribute Money'**
  String get distributeMoney;

  /// No description provided for @returnMoney.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnMoney;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @chooseSender.
  ///
  /// In en, this message translates to:
  /// **'Choose Sender'**
  String get chooseSender;

  /// No description provided for @chooseReceiver.
  ///
  /// In en, this message translates to:
  /// **'Choose Receiver'**
  String get chooseReceiver;

  /// No description provided for @transferTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer Money'**
  String get transferTitle;

  /// No description provided for @transferredOut.
  ///
  /// In en, this message translates to:
  /// **'Transferred Out'**
  String get transferredOut;

  /// No description provided for @receivedFrom.
  ///
  /// In en, this message translates to:
  /// **'Received From'**
  String get receivedFrom;

  /// No description provided for @transferredTo.
  ///
  /// In en, this message translates to:
  /// **'{sender} transferred to {receiver}'**
  String transferredTo(Object sender, Object receiver);

  /// No description provided for @receivedFromName.
  ///
  /// In en, this message translates to:
  /// **'{receiver} received from {sender}'**
  String receivedFromName(Object receiver, Object sender);

  /// No description provided for @transferFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to record transfer'**
  String get transferFailed;

  /// No description provided for @recordPurchase.
  ///
  /// In en, this message translates to:
  /// **'Record Purchase'**
  String get recordPurchase;

  /// No description provided for @purchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchase;

  /// No description provided for @coffeePurchase.
  ///
  /// In en, this message translates to:
  /// **'Coffee Purchase'**
  String get coffeePurchase;

  /// No description provided for @transactionCompletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Transaction completed successfully'**
  String get transactionCompletedSuccessfully;

  /// No description provided for @profileUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccessfully;

  /// No description provided for @workerDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Collector deleted successfully'**
  String get workerDeletedSuccessfully;

  /// No description provided for @workerSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Collector saved successfully'**
  String get workerSavedSuccessfully;

  /// No description provided for @backupSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Backup Successful'**
  String get backupSuccessful;

  /// No description provided for @insufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance'**
  String get insufficientBalance;

  /// No description provided for @workerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Collector not found'**
  String get workerNotFound;

  /// No description provided for @notificationSent.
  ///
  /// In en, this message translates to:
  /// **'Notification sent'**
  String get notificationSent;

  /// No description provided for @errorOccurred.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorOccurred;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait...'**
  String get pleaseWait;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get noTransactionsYet;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @endOfTransactions.
  ///
  /// In en, this message translates to:
  /// **'— End of transactions —'**
  String get endOfTransactions;

  /// No description provided for @companyName.
  ///
  /// In en, this message translates to:
  /// **'Company Name'**
  String get companyName;

  /// No description provided for @companyAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get companyAddress;

  /// No description provided for @companyPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get companyPhone;

  /// No description provided for @maxDistributionLimit.
  ///
  /// In en, this message translates to:
  /// **'Max Distribution Limit ({currency})'**
  String maxDistributionLimit(Object currency);

  /// No description provided for @topBuyer.
  ///
  /// In en, this message translates to:
  /// **'Top Buyer'**
  String get topBuyer;

  /// No description provided for @commission.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get commission;

  /// No description provided for @purchased.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get purchased;

  /// No description provided for @purchasesByType.
  ///
  /// In en, this message translates to:
  /// **'Coffee Purchases by Type'**
  String get purchasesByType;

  /// No description provided for @quickNotes.
  ///
  /// In en, this message translates to:
  /// **'Quick Notes'**
  String get quickNotes;

  /// No description provided for @cashPayment.
  ///
  /// In en, this message translates to:
  /// **'Cash payment'**
  String get cashPayment;

  /// No description provided for @creditToCollect.
  ///
  /// In en, this message translates to:
  /// **'Credit - to collect'**
  String get creditToCollect;

  /// No description provided for @qualityGood.
  ///
  /// In en, this message translates to:
  /// **'Quality: Good'**
  String get qualityGood;

  /// No description provided for @qualityAverage.
  ///
  /// In en, this message translates to:
  /// **'Quality: Average'**
  String get qualityAverage;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me'**
  String get rememberMe;

  /// No description provided for @addWorker.
  ///
  /// In en, this message translates to:
  /// **'Add Collector'**
  String get addWorker;

  /// No description provided for @editWorker.
  ///
  /// In en, this message translates to:
  /// **'Edit Collector'**
  String get editWorker;

  /// No description provided for @workerName.
  ///
  /// In en, this message translates to:
  /// **'Collector Name'**
  String get workerName;

  /// No description provided for @workerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get workerPhone;

  /// No description provided for @workerRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get workerRole;

  /// No description provided for @yearsOfExperience.
  ///
  /// In en, this message translates to:
  /// **'Years of Experience'**
  String get yearsOfExperience;

  /// No description provided for @createLoginAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Login Account'**
  String get createLoginAccount;

  /// No description provided for @todayTopBuyer.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Top Buyer'**
  String get todayTopBuyer;

  /// No description provided for @avgPriceToday.
  ///
  /// In en, this message translates to:
  /// **'Average Price Today'**
  String get avgPriceToday;

  /// No description provided for @commissionPaidToday.
  ///
  /// In en, this message translates to:
  /// **'Commission Paid Today'**
  String get commissionPaidToday;

  /// No description provided for @lowBalanceAlert.
  ///
  /// In en, this message translates to:
  /// **'Low Balance Alert'**
  String get lowBalanceAlert;

  /// No description provided for @moneyReceived.
  ///
  /// In en, this message translates to:
  /// **'Money Received'**
  String get moneyReceived;

  /// No description provided for @purchaseRecorded.
  ///
  /// In en, this message translates to:
  /// **'Purchase Recorded'**
  String get purchaseRecorded;

  /// No description provided for @viewSystemLogs.
  ///
  /// In en, this message translates to:
  /// **'View system activity logs'**
  String get viewSystemLogs;

  /// No description provided for @backupExportClear.
  ///
  /// In en, this message translates to:
  /// **'Backup, Export, Clear Cache'**
  String get backupExportClear;

  /// No description provided for @onlyViewersCanEdit.
  ///
  /// In en, this message translates to:
  /// **'Business settings can only be edited by viewers (owners).'**
  String get onlyViewersCanEdit;

  /// No description provided for @showingTransactions.
  ///
  /// In en, this message translates to:
  /// **'Showing {count} of {total} transactions'**
  String showingTransactions(Object count, Object total);

  /// No description provided for @remainingItems.
  ///
  /// In en, this message translates to:
  /// **'{count} remaining'**
  String remainingItems(Object count);

  /// No description provided for @showingAllTransactions.
  ///
  /// In en, this message translates to:
  /// **'Showing all {count} transactions'**
  String showingAllTransactions(Object count);

  /// No description provided for @enterMessage.
  ///
  /// In en, this message translates to:
  /// **'Please enter a message'**
  String get enterMessage;

  /// No description provided for @errorSendingPing.
  ///
  /// In en, this message translates to:
  /// **'Error sending ping: {error}'**
  String errorSendingPing(Object error);

  /// No description provided for @workerAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Collector Account Created!'**
  String get workerAccountCreated;

  /// No description provided for @loginCredentialsFor.
  ///
  /// In en, this message translates to:
  /// **'Login credentials for {name}:'**
  String loginCredentialsFor(Object name);

  /// No description provided for @sendCredentialsToWorker.
  ///
  /// In en, this message translates to:
  /// **'Send these credentials to the collector:'**
  String get sendCredentialsToWorker;

  /// No description provided for @welcomeToCofiz.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Cofiz!'**
  String get welcomeToCofiz;

  /// No description provided for @credentialsCopied.
  ///
  /// In en, this message translates to:
  /// **'Credentials copied to clipboard'**
  String get credentialsCopied;

  /// No description provided for @couldNotOpenSms.
  ///
  /// In en, this message translates to:
  /// **'Could not open SMS app'**
  String get couldNotOpenSms;

  /// No description provided for @downloadAppMessage.
  ///
  /// In en, this message translates to:
  /// **'Download the app and login to start tracking your sales.'**
  String get downloadAppMessage;

  /// No description provided for @allActions.
  ///
  /// In en, this message translates to:
  /// **'All Actions'**
  String get allActions;

  /// No description provided for @accessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access Denied'**
  String get accessDenied;

  /// No description provided for @adminAuditLogsOnly.
  ///
  /// In en, this message translates to:
  /// **'Only administrators can view audit logs'**
  String get adminAuditLogsOnly;

  /// No description provided for @filtering.
  ///
  /// In en, this message translates to:
  /// **'Filtering: {filter}'**
  String filtering(Object filter);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @errorLoadingLogs.
  ///
  /// In en, this message translates to:
  /// **'Error loading logs'**
  String get errorLoadingLogs;

  /// No description provided for @noAuditLogs.
  ///
  /// In en, this message translates to:
  /// **'No Audit Logs'**
  String get noAuditLogs;

  /// No description provided for @activityLogsWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Activity logs will appear here'**
  String get activityLogsWillAppear;

  /// No description provided for @signInToWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your workspace.'**
  String get signInToWorkspace;

  /// No description provided for @thisFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get thisFieldRequired;

  /// No description provided for @validEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get validEmailRequired;

  /// No description provided for @passwordLengthError.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordLengthError;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @passwordResetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to {email}'**
  String passwordResetLinkSent(Object email);

  /// No description provided for @failedToSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset link'**
  String get failedToSendResetLink;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLink;

  /// No description provided for @enterEmailResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address and we\'ll send you a link to reset your password.'**
  String get enterEmailResetPassword;

  /// No description provided for @pingAllWorkers.
  ///
  /// In en, this message translates to:
  /// **'Ping All Collectors'**
  String get pingAllWorkers;

  /// No description provided for @messageToAllWorkers.
  ///
  /// In en, this message translates to:
  /// **'Message to all collectors'**
  String get messageToAllWorkers;

  /// No description provided for @announcement.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get announcement;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @notificationSentToAll.
  ///
  /// In en, this message translates to:
  /// **'Notification sent to all collectors'**
  String get notificationSentToAll;

  /// No description provided for @markAllAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllAsRead;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String minutesAgo(Object minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String hoursAgo(Object hours);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String daysAgo(Object days);

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days'**
  String get last7Days;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All Time'**
  String get allTime;

  /// No description provided for @chooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose Date'**
  String get chooseDate;

  /// No description provided for @preparingPdfReport.
  ///
  /// In en, this message translates to:
  /// **'Preparing PDF Report...'**
  String get preparingPdfReport;

  /// No description provided for @noTransactionsFound.
  ///
  /// In en, this message translates to:
  /// **'No transactions found'**
  String get noTransactionsFound;

  /// No description provided for @records.
  ///
  /// In en, this message translates to:
  /// **'records'**
  String get records;

  /// No description provided for @business.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get business;

  /// No description provided for @manageAreas.
  ///
  /// In en, this message translates to:
  /// **'Manage Areas'**
  String get manageAreas;

  /// No description provided for @purchaseLocations.
  ///
  /// In en, this message translates to:
  /// **'Purchase locations'**
  String get purchaseLocations;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @backupExportClearCache.
  ///
  /// In en, this message translates to:
  /// **'Backup, Export, Clear Cache'**
  String get backupExportClearCache;

  /// No description provided for @viewSystemActivityLogs.
  ///
  /// In en, this message translates to:
  /// **'View system activity logs'**
  String get viewSystemActivityLogs;

  /// No description provided for @app.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get app;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(Object version);

  /// No description provided for @passwordResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent to {email}'**
  String passwordResetEmailSent(Object email);

  /// No description provided for @failedToSendResetEmail.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset email: {error}'**
  String failedToSendResetEmail(Object error);

  /// No description provided for @changePasswordDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordDialogTitle;

  /// No description provided for @changePasswordDialogContent.
  ///
  /// In en, this message translates to:
  /// **'To change your password, we will send a password reset link to your email address. Do you want to proceed?'**
  String get changePasswordDialogContent;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get updateFailed;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @enterYourName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterYourName;

  /// No description provided for @pleaseEnterYourName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterYourName;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @emailCannotBeChanged.
  ///
  /// In en, this message translates to:
  /// **'Email cannot be changed'**
  String get emailCannotBeChanged;

  /// No description provided for @emailNotifications.
  ///
  /// In en, this message translates to:
  /// **'Email Notifications'**
  String get emailNotifications;

  /// No description provided for @receiveUpdatesViaEmail.
  ///
  /// In en, this message translates to:
  /// **'Receive updates via email'**
  String get receiveUpdatesViaEmail;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotifications;

  /// No description provided for @receiveInstantAlerts.
  ///
  /// In en, this message translates to:
  /// **'Receive instant alerts on your device'**
  String get receiveInstantAlerts;

  /// No description provided for @verifyEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get verifyEmail;

  /// No description provided for @emailVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get emailVerified;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resendCode;

  /// No description provided for @enterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Enter verification code'**
  String get enterVerificationCode;

  /// No description provided for @codeSentToEmail.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent to your email'**
  String get codeSentToEmail;

  /// No description provided for @emailVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get emailVerifiedSuccess;

  /// No description provided for @codeSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send code. Try again.'**
  String get codeSendFailed;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code. Try again.'**
  String get invalidCode;

  /// No description provided for @codeExpired.
  ///
  /// In en, this message translates to:
  /// **'Code expired. Please resend a new code.'**
  String get codeExpired;

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts - resend code'**
  String get tooManyAttempts;

  /// No description provided for @attemptsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} attempts remaining'**
  String attemptsRemaining(Object count);

  /// No description provided for @businessSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Business settings saved successfully'**
  String get businessSettingsSaved;

  /// No description provided for @errorSavingSettings.
  ///
  /// In en, this message translates to:
  /// **'Error saving settings: {error}'**
  String errorSavingSettings(Object error);

  /// No description provided for @companyInformation.
  ///
  /// In en, this message translates to:
  /// **'Company Information'**
  String get companyInformation;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @businessLimits.
  ///
  /// In en, this message translates to:
  /// **'Business Limits'**
  String get businessLimits;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid number'**
  String get invalidNumber;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legal;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// No description provided for @contactDetails.
  ///
  /// In en, this message translates to:
  /// **'Contact Details'**
  String get contactDetails;

  /// No description provided for @visitWebsite.
  ///
  /// In en, this message translates to:
  /// **'Visit Website'**
  String get visitWebsite;

  /// No description provided for @copyright.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Cofiz app. All rights reserved.'**
  String get copyright;

  /// No description provided for @areaAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Area already exists'**
  String get areaAlreadyExists;

  /// No description provided for @areaAdded.
  ///
  /// In en, this message translates to:
  /// **'Area \"{name}\" added'**
  String areaAdded(Object name);

  /// No description provided for @deleteArea.
  ///
  /// In en, this message translates to:
  /// **'Delete Area'**
  String get deleteArea;

  /// No description provided for @deleteAreaConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteAreaConfirmation(Object name);

  /// No description provided for @areaDeleted.
  ///
  /// In en, this message translates to:
  /// **'Area \"{name}\" deleted'**
  String areaDeleted(Object name);

  /// No description provided for @editArea.
  ///
  /// In en, this message translates to:
  /// **'Edit Area'**
  String get editArea;

  /// No description provided for @areaName.
  ///
  /// In en, this message translates to:
  /// **'Area Name'**
  String get areaName;

  /// No description provided for @areaRenamed.
  ///
  /// In en, this message translates to:
  /// **'Area renamed to \"{name}\"'**
  String areaRenamed(Object name);

  /// No description provided for @enterNewAreaName.
  ///
  /// In en, this message translates to:
  /// **'Enter new area name...'**
  String get enterNewAreaName;

  /// No description provided for @noAreasYet.
  ///
  /// In en, this message translates to:
  /// **'No areas yet'**
  String get noAreasYet;

  /// No description provided for @addYourFirstArea.
  ///
  /// In en, this message translates to:
  /// **'Add your first area above'**
  String get addYourFirstArea;

  /// No description provided for @defaultArea.
  ///
  /// In en, this message translates to:
  /// **'Default area'**
  String get defaultArea;

  /// No description provided for @dataExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Data exported to:\n\n{path}\n\nYou can access this file from your device file manager.'**
  String dataExportedTo(Object path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(Object error);

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache?'**
  String get clearCache;

  /// No description provided for @clearCacheConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will clear local preferences (theme, settings, last login). It will NOT delete collectors or transactions.\n\nAre you sure?'**
  String get clearCacheConfirmation;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared. Please restart app for full effect.'**
  String get cacheCleared;

  /// No description provided for @backupAndExport.
  ///
  /// In en, this message translates to:
  /// **'Backup & Export'**
  String get backupAndExport;

  /// No description provided for @exportDataJson.
  ///
  /// In en, this message translates to:
  /// **'Export Data (JSON)'**
  String get exportDataJson;

  /// No description provided for @exportDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save a full backup of all collectors and transactions to your device.'**
  String get exportDataSubtitle;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @clearAppCache.
  ///
  /// In en, this message translates to:
  /// **'Clear App Cache'**
  String get clearAppCache;

  /// No description provided for @clearAppCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reset local preferences and temporary files.'**
  String get clearAppCacheSubtitle;

  /// No description provided for @failedToDeleteWorker.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete collector'**
  String get failedToDeleteWorker;

  /// No description provided for @deleteTransactionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Transaction'**
  String get deleteTransactionTitle;

  /// No description provided for @deleteTransactionConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this transaction of {amount}? The collector\'s balance will be updated.'**
  String deleteTransactionConfirmation(Object amount);

  /// No description provided for @transactionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Transaction deleted'**
  String get transactionDeleted;

  /// No description provided for @failedToDeleteTransaction.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete transaction'**
  String get failedToDeleteTransaction;

  /// No description provided for @distribute.
  ///
  /// In en, this message translates to:
  /// **'Distribute'**
  String get distribute;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performance;

  /// No description provided for @transactionsWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Transactions will appear here'**
  String get transactionsWillAppearHere;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @couldNotMakeCall.
  ///
  /// In en, this message translates to:
  /// **'Could not make call: {error}'**
  String couldNotMakeCall(Object error);

  /// No description provided for @couldNotSendSMS.
  ///
  /// In en, this message translates to:
  /// **'Could not send SMS: {error}'**
  String couldNotSendSMS(Object error);

  /// No description provided for @yearsExperience.
  ///
  /// In en, this message translates to:
  /// **'{years} years experience'**
  String yearsExperience(Object years);

  /// No description provided for @emailRequiredForLogin.
  ///
  /// In en, this message translates to:
  /// **'Email is required to create a login account'**
  String get emailRequiredForLogin;

  /// No description provided for @workerSavedAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Collector saved, but login account failed: {error}'**
  String workerSavedAccountFailed(Object error);

  /// No description provided for @workerUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Collector updated successfully'**
  String get workerUpdatedSuccessfully;

  /// No description provided for @workerAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Collector added successfully'**
  String get workerAddedSuccessfully;

  /// No description provided for @failedToSaveWorker.
  ///
  /// In en, this message translates to:
  /// **'Failed to save collector'**
  String get failedToSaveWorker;

  /// No description provided for @nameIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameIsRequired;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @phoneNumberIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get phoneNumberIsRequired;

  /// No description provided for @commissionRateIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Commission rate is required'**
  String get commissionRateIsRequired;

  /// No description provided for @enterValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get enterValidNumber;

  /// No description provided for @emailRequiredLogin.
  ///
  /// In en, this message translates to:
  /// **'Email (Required for login)'**
  String get emailRequiredLogin;

  /// No description provided for @emailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (Optional)'**
  String get emailOptional;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get enterValidEmail;

  /// No description provided for @allowWorkerLogin.
  ///
  /// In en, this message translates to:
  /// **'Allow this collector to login to the app'**
  String get allowWorkerLogin;

  /// No description provided for @years.
  ///
  /// In en, this message translates to:
  /// **'{count} years'**
  String years(Object count);

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @performanceRating.
  ///
  /// In en, this message translates to:
  /// **'Performance Rating'**
  String get performanceRating;

  /// No description provided for @filterWorkers.
  ///
  /// In en, this message translates to:
  /// **'Filter Collectors'**
  String get filterWorkers;

  /// No description provided for @tryAdjustingSearch.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your search'**
  String get tryAdjustingSearch;

  /// No description provided for @tapToAddWorker.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add your first collector'**
  String get tapToAddWorker;

  /// No description provided for @returnMoneyTitle.
  ///
  /// In en, this message translates to:
  /// **'Return Money'**
  String get returnMoneyTitle;

  /// No description provided for @transaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get transaction;

  /// No description provided for @errorPickingImage.
  ///
  /// In en, this message translates to:
  /// **'Error picking image: {error}'**
  String errorPickingImage(Object error);

  /// No description provided for @failedToUploadReceipt.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload receipt'**
  String get failedToUploadReceipt;

  /// No description provided for @receipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receipt;

  /// No description provided for @receiptDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Receipt downloaded'**
  String get receiptDownloaded;

  /// No description provided for @failedToDownloadReceipt.
  ///
  /// In en, this message translates to:
  /// **'Failed to download receipt'**
  String get failedToDownloadReceipt;

  /// No description provided for @transactionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Transaction completed successfully'**
  String get transactionCompleted;

  /// No description provided for @failedToComplete.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete transaction'**
  String get failedToComplete;

  /// No description provided for @amountWithCurrency.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String amountWithCurrency(Object currency);

  /// No description provided for @amountIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get amountIsRequired;

  /// No description provided for @invalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount'**
  String get invalidAmount;

  /// No description provided for @selectCoffeeType.
  ///
  /// In en, this message translates to:
  /// **'Please select a coffee type'**
  String get selectCoffeeType;

  /// No description provided for @weightKg.
  ///
  /// In en, this message translates to:
  /// **'Weight (Kg)'**
  String get weightKg;

  /// No description provided for @totalCostCalculated.
  ///
  /// In en, this message translates to:
  /// **'Total Cost (Calculated)'**
  String get totalCostCalculated;

  /// No description provided for @notesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes (Optional)'**
  String get notesOptional;

  /// No description provided for @addNotesHere.
  ///
  /// In en, this message translates to:
  /// **'Add any notes here...'**
  String get addNotesHere;

  /// No description provided for @receiptSelected.
  ///
  /// In en, this message translates to:
  /// **'Receipt Selected'**
  String get receiptSelected;

  /// No description provided for @addReceiptPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Receipt Photo'**
  String get addReceiptPhoto;

  /// No description provided for @workerDataNotFound.
  ///
  /// In en, this message translates to:
  /// **'Collector data not found'**
  String get workerDataNotFound;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @lowBalanceWarning.
  ///
  /// In en, this message translates to:
  /// **'Low balance - please return funds'**
  String get lowBalanceWarning;

  /// No description provided for @balanceGood.
  ///
  /// In en, this message translates to:
  /// **'Balance looks good'**
  String get balanceGood;

  /// No description provided for @recordReturn.
  ///
  /// In en, this message translates to:
  /// **'Record Return'**
  String get recordReturn;

  /// No description provided for @offlineSyncPending.
  ///
  /// In en, this message translates to:
  /// **'Offline • {count} pending'**
  String offlineSyncPending(Object count);

  /// No description provided for @youAreOffline.
  ///
  /// In en, this message translates to:
  /// **'You are offline'**
  String get youAreOffline;

  /// No description provided for @yrs.
  ///
  /// In en, this message translates to:
  /// **'{count} yrs'**
  String yrs(Object count);

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @recordCoffeePurchaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Coffee Purchase'**
  String get recordCoffeePurchaseTitle;

  /// No description provided for @recordCoffeePurchaseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record coffee purchased from farmers'**
  String get recordCoffeePurchaseSubtitle;

  /// No description provided for @coffeeTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Coffee Type *'**
  String get coffeeTypeLabel;

  /// No description provided for @quantityKgLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity (Kg) *'**
  String get quantityKgLabel;

  /// No description provided for @pricePerKgLabel.
  ///
  /// In en, this message translates to:
  /// **'Price/Kg ({currency}) *'**
  String pricePerKgLabel(Object currency);

  /// No description provided for @yourCommission.
  ///
  /// In en, this message translates to:
  /// **'Your Commission:'**
  String get yourCommission;

  /// No description provided for @commissionRateInfo.
  ///
  /// In en, this message translates to:
  /// **'Rate: {currency} {rate} per Kg'**
  String commissionRateInfo(Object currency, Object rate);

  /// No description provided for @purchaseLocation.
  ///
  /// In en, this message translates to:
  /// **'Purchase Location'**
  String get purchaseLocation;

  /// No description provided for @noAreasConfigured.
  ///
  /// In en, this message translates to:
  /// **'No areas configured. Add areas in Settings.'**
  String get noAreasConfigured;

  /// No description provided for @placeLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Place / Location (if not in list above)'**
  String get placeLocationLabel;

  /// No description provided for @notesDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes (details...)'**
  String get notesDetailsLabel;

  /// No description provided for @availableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available: {currency} {amount}'**
  String availableBalance(Object amount, Object currency);

  /// No description provided for @insufficient.
  ///
  /// In en, this message translates to:
  /// **' — Insufficient!'**
  String get insufficient;

  /// No description provided for @insufficientBalanceForPurchase.
  ///
  /// In en, this message translates to:
  /// **'Insufficient balance for this purchase'**
  String get insufficientBalanceForPurchase;

  /// No description provided for @locationPrefix.
  ///
  /// In en, this message translates to:
  /// **'Location: {place}'**
  String locationPrefix(Object place);

  /// No description provided for @purchaseRecordedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Purchase recorded! Commission: {currency} {commission}'**
  String purchaseRecordedSuccess(Object commission, Object currency);

  /// No description provided for @failedToRecordPurchase.
  ///
  /// In en, this message translates to:
  /// **'Failed to record purchase'**
  String get failedToRecordPurchase;

  /// No description provided for @recordReturnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record money you are returning to the admin'**
  String get recordReturnSubtitle;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String amountLabel(Object currency);

  /// No description provided for @pleaseEnterAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter an amount'**
  String get pleaseEnterAmount;

  /// No description provided for @pleaseEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get pleaseEnterValidAmount;

  /// No description provided for @amountExceedsBalance.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds your current balance'**
  String get amountExceedsBalance;

  /// No description provided for @currentBalanceInfo.
  ///
  /// In en, this message translates to:
  /// **'Current balance: {currency} {balance}'**
  String currentBalanceInfo(Object balance, Object currency);

  /// No description provided for @returnRecordedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Return recorded successfully!'**
  String get returnRecordedSuccess;

  /// No description provided for @failedToRecordReturn.
  ///
  /// In en, this message translates to:
  /// **'Failed to record return'**
  String get failedToRecordReturn;

  /// No description provided for @expenseRecorded.
  ///
  /// In en, this message translates to:
  /// **'Expense recorded successfully'**
  String get expenseRecorded;

  /// No description provided for @incomeRecorded.
  ///
  /// In en, this message translates to:
  /// **'Income recorded successfully'**
  String get incomeRecorded;

  /// No description provided for @editIncome.
  ///
  /// In en, this message translates to:
  /// **'Edit Income'**
  String get editIncome;

  /// No description provided for @editExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit Expense'**
  String get editExpense;

  /// No description provided for @incomeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Income deleted'**
  String get incomeDeleted;

  /// No description provided for @expenseDeleted.
  ///
  /// In en, this message translates to:
  /// **'Expense deleted'**
  String get expenseDeleted;

  /// No description provided for @failedToDeleteIncome.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete income'**
  String get failedToDeleteIncome;

  /// No description provided for @failedToDeleteExpense.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete expense'**
  String get failedToDeleteExpense;

  /// No description provided for @deleteIncomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Income'**
  String get deleteIncomeTitle;

  /// No description provided for @deleteIncomeConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this income of {amount}?'**
  String deleteIncomeConfirmation(Object amount);

  /// No description provided for @deleteExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Expense'**
  String get deleteExpenseTitle;

  /// No description provided for @deleteExpenseConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this expense of {amount}?'**
  String deleteExpenseConfirmation(Object amount);

  /// No description provided for @moneyReturnedTitle.
  ///
  /// In en, this message translates to:
  /// **'Money Returned'**
  String get moneyReturnedTitle;

  /// No description provided for @coffeePurchaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Coffee Purchase'**
  String get coffeePurchaseTitle;

  /// No description provided for @kg.
  ///
  /// In en, this message translates to:
  /// **'Kg'**
  String get kg;

  /// No description provided for @pingMessageHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Please submit your daily report'**
  String get pingMessageHint;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @loginCredentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cofiz Login Credentials'**
  String get loginCredentialsTitle;

  /// No description provided for @pingWorkerTitle.
  ///
  /// In en, this message translates to:
  /// **'Ping {name}'**
  String pingWorkerTitle(Object name);

  /// No description provided for @messageFromAdmin.
  ///
  /// In en, this message translates to:
  /// **'Message from Admin'**
  String get messageFromAdmin;

  /// No description provided for @notificationSentToUser.
  ///
  /// In en, this message translates to:
  /// **'Notification sent to {name}'**
  String notificationSentToUser(Object name);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @errorGeneratingReport.
  ///
  /// In en, this message translates to:
  /// **'Error generating report'**
  String get errorGeneratingReport;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'remaining'**
  String get remaining;

  /// No description provided for @pingWorker.
  ///
  /// In en, this message translates to:
  /// **'Ping'**
  String get pingWorker;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategory;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add Expense'**
  String get addExpense;

  /// No description provided for @addIncome.
  ///
  /// In en, this message translates to:
  /// **'Add Income'**
  String get addIncome;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category Name'**
  String get categoryName;

  /// No description provided for @collector.
  ///
  /// In en, this message translates to:
  /// **'Collector'**
  String get collector;

  /// No description provided for @collectors.
  ///
  /// In en, this message translates to:
  /// **'Collectors'**
  String get collectors;

  /// No description provided for @companyIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get companyIncome;

  /// No description provided for @defaultCategoriesCannotBeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Default categories cannot be deleted'**
  String get defaultCategoriesCannotBeDeleted;

  /// No description provided for @expenseDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get expenseDescription;

  /// No description provided for @expenseRecords.
  ///
  /// In en, this message translates to:
  /// **'Expense Records'**
  String get expenseRecords;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @incomeBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Income Breakdown'**
  String get incomeBreakdown;

  /// No description provided for @incomeDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get incomeDescription;

  /// No description provided for @incomeRecords.
  ///
  /// In en, this message translates to:
  /// **'Income Records'**
  String get incomeRecords;

  /// No description provided for @investment.
  ///
  /// In en, this message translates to:
  /// **'Investment'**
  String get investment;

  /// No description provided for @investmentIncome.
  ///
  /// In en, this message translates to:
  /// **'Investment Income'**
  String get investmentIncome;

  /// No description provided for @latestTransactions.
  ///
  /// In en, this message translates to:
  /// **'Latest Transactions'**
  String get latestTransactions;

  /// No description provided for @manageExpenseCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage Expense Categories'**
  String get manageExpenseCategories;

  /// No description provided for @manageSaleCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage Sale Categories'**
  String get manageSaleCategories;

  /// No description provided for @manualSales.
  ///
  /// In en, this message translates to:
  /// **'Manual Sales'**
  String get manualSales;

  /// No description provided for @moneyIn.
  ///
  /// In en, this message translates to:
  /// **'Cash In'**
  String get moneyIn;

  /// No description provided for @moneyOut.
  ///
  /// In en, this message translates to:
  /// **'Cash Out'**
  String get moneyOut;

  /// No description provided for @myInvestments.
  ///
  /// In en, this message translates to:
  /// **'My Investments'**
  String get myInvestments;

  /// No description provided for @noViewersFound.
  ///
  /// In en, this message translates to:
  /// **'No viewers found'**
  String get noViewersFound;

  /// No description provided for @recordExpense.
  ///
  /// In en, this message translates to:
  /// **'Record Expense'**
  String get recordExpense;

  /// No description provided for @recordInvestment.
  ///
  /// In en, this message translates to:
  /// **'Record Investment'**
  String get recordInvestment;

  /// No description provided for @recordSale.
  ///
  /// In en, this message translates to:
  /// **'Record Sale'**
  String get recordSale;

  /// No description provided for @recordedBy.
  ///
  /// In en, this message translates to:
  /// **'Recorded by'**
  String get recordedBy;

  /// No description provided for @sale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get sale;

  /// No description provided for @salesIncome.
  ///
  /// In en, this message translates to:
  /// **'Sales Income'**
  String get salesIncome;

  /// No description provided for @selectExpenseCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Expense Category'**
  String get selectExpenseCategory;

  /// No description provided for @selectSaleCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Category'**
  String get selectSaleCategory;

  /// No description provided for @selectViewer.
  ///
  /// In en, this message translates to:
  /// **'Select Viewer'**
  String get selectViewer;

  /// No description provided for @selectSource.
  ///
  /// In en, this message translates to:
  /// **'Select Source'**
  String get selectSource;

  /// No description provided for @totalExpenses.
  ///
  /// In en, this message translates to:
  /// **'Total Expenses'**
  String get totalExpenses;

  /// No description provided for @totalIncome.
  ///
  /// In en, this message translates to:
  /// **'Total Income'**
  String get totalIncome;

  /// No description provided for @viewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get viewer;

  /// No description provided for @viewerInvestment.
  ///
  /// In en, this message translates to:
  /// **'Investment'**
  String get viewerInvestment;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @pendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'Pending Approvals'**
  String get pendingApprovals;

  /// No description provided for @approveAll.
  ///
  /// In en, this message translates to:
  /// **'Confirm All'**
  String get approveAll;

  /// No description provided for @noPendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'No entries waiting for confirmation'**
  String get noPendingApprovals;

  /// No description provided for @allConfirmed.
  ///
  /// In en, this message translates to:
  /// **'All entries confirmed'**
  String get allConfirmed;

  /// No description provided for @entryConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Entry confirmed'**
  String get entryConfirmed;

  /// No description provided for @editTransaction.
  ///
  /// In en, this message translates to:
  /// **'Edit Transaction'**
  String get editTransaction;

  /// No description provided for @recordTransactions.
  ///
  /// In en, this message translates to:
  /// **'Record Transactions'**
  String get recordTransactions;

  /// No description provided for @selectCollector.
  ///
  /// In en, this message translates to:
  /// **'Select Collector'**
  String get selectCollector;

  /// No description provided for @searchCollector.
  ///
  /// In en, this message translates to:
  /// **'Search collectors'**
  String get searchCollector;

  /// No description provided for @noCollectorsFound.
  ///
  /// In en, this message translates to:
  /// **'No collectors found'**
  String get noCollectorsFound;

  /// No description provided for @enterSourceName.
  ///
  /// In en, this message translates to:
  /// **'Type the source name'**
  String get enterSourceName;

  /// No description provided for @filterByDate.
  ///
  /// In en, this message translates to:
  /// **'Filter by date'**
  String get filterByDate;

  /// No description provided for @cashFlow.
  ///
  /// In en, this message translates to:
  /// **'Cash flow'**
  String get cashFlow;

  /// No description provided for @neutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get neutral;

  /// No description provided for @tapAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Tap back again to exit'**
  String get tapAgainToExit;

  /// No description provided for @lockedEntry.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get lockedEntry;

  /// No description provided for @lockedReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin override required'**
  String get lockedReasonTitle;

  /// No description provided for @lockedReasonMessage.
  ///
  /// In en, this message translates to:
  /// **'This entry is older than 7 days and is locked. Enter a reason to {action} it.'**
  String lockedReasonMessage(Object action);

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reasonLabel;

  /// No description provided for @reasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why are you changing this entry?'**
  String get reasonHint;

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A reason is required to override a locked entry.'**
  String get reasonRequired;

  /// No description provided for @transactionUpdated.
  ///
  /// In en, this message translates to:
  /// **'Transaction updated'**
  String get transactionUpdated;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['am', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'am':
      return AppLocalizationsAm();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
