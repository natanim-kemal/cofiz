// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Cofiz';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get workers => 'Collectors';

  @override
  String get reports => 'Reports';

  @override
  String get settings => 'Settings';

  @override
  String get welcomeBack => 'Welcome Back,';

  @override
  String get changeLanguage => 'Change Language';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get cancel => 'Cancel';

  @override
  String get todaysActivity => 'Today\'s Activity';

  @override
  String get totalActivity => 'Total Activity';

  @override
  String get distributed => 'Distributed';

  @override
  String get returned => 'Returned';

  @override
  String get netBalance => 'Net Balance';

  @override
  String get activeWorkers => 'Collectors';

  @override
  String get viewAll => 'View All';

  @override
  String get total => 'Total';

  @override
  String get active => 'Active';

  @override
  String get perf => 'Perf';

  @override
  String get sales => 'Sales';

  @override
  String get noWorkersYet => 'No collectors yet';

  @override
  String get addWorkersToGetStarted => 'Add collectors to get started';

  @override
  String get currency => 'ETB';

  @override
  String get searchWorkers => 'Search collectors...';

  @override
  String get noWorkersFound => 'No collectors found';

  @override
  String get profile => 'Profile';

  @override
  String get notifications => 'Notifications';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get security => 'Security';

  @override
  String get changePassword => 'Change Password';

  @override
  String get twoFactorAuth => 'Two-Factor Authentication';

  @override
  String get signOut => 'Sign Out';

  @override
  String get areYouSureSignOut => 'Are you sure you want to sign out?';

  @override
  String get confirm => 'Confirm';

  @override
  String get export => 'Export';

  @override
  String get noDataToExport => 'No data to export';

  @override
  String get manageYourAccount => 'Manage your account';

  @override
  String get customizeAlerts => 'Customize alerts';

  @override
  String get systemDefault => 'System default';

  @override
  String get weeklyActivity => 'Weekly Activity';

  @override
  String get aboutCofiz => 'About Cofiz';

  @override
  String get auditLogs => 'Audit Logs';

  @override
  String get businessSettings => 'Business Settings';

  @override
  String get businessInformation => 'Business Information';

  @override
  String get dataManagement => 'Data Management';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get send => 'Send';

  @override
  String get sendEmail => 'Send Email';

  @override
  String get sendSms => 'Send SMS';

  @override
  String get retry => 'Retry';

  @override
  String get ok => 'OK';

  @override
  String get goBack => 'Go Back';

  @override
  String get submitReport => 'Submit Report';

  @override
  String get loadMore => 'Load More';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get offline => 'Offline';

  @override
  String get busy => 'Busy';

  @override
  String get all => 'All';

  @override
  String get filter => 'Filter';

  @override
  String get historyDescription => 'View your transaction history';

  @override
  String get type => 'Type';

  @override
  String get qty => 'Qty';

  @override
  String get avgPrice => 'Avg Price';

  @override
  String get workerCommission => 'Collector Commission:';

  @override
  String get commissionEarned => 'Commission Earned';

  @override
  String get commissionRate => 'Commission Rate (per Kg)';

  @override
  String get balance => 'Balance';

  @override
  String get currentBalance => 'Current Balance';

  @override
  String get totalDistributed => 'Total Distributed';

  @override
  String get totalReturned => 'Total Returned';

  @override
  String get coffeePurchased => 'Coffee Purchased';

  @override
  String get totalCoffeePurchased => 'Total Coffee Purchased';

  @override
  String get transactions => 'Transactions';

  @override
  String get transactionHistory => 'Transaction History';

  @override
  String get recentTransactions => 'Recent Transactions';

  @override
  String get jenfel => 'Jenfel';

  @override
  String get yetatebe => 'Yetatebe';

  @override
  String get special => 'Special';

  @override
  String get coffeeType => 'Coffee Type';

  @override
  String get quantity => 'Quantity';

  @override
  String get pricePerKg => 'Price/Kg';

  @override
  String get weight => 'Weight';

  @override
  String get totalAmount => 'Total Amount:';

  @override
  String get distributeMoney => 'Distribute Money';

  @override
  String get returnMoney => 'Return';

  @override
  String get transfer => 'Transfer';

  @override
  String get chooseSender => 'Choose Sender';

  @override
  String get chooseReceiver => 'Choose Receiver';

  @override
  String get transferTitle => 'Transfer Money';

  @override
  String get transferredOut => 'Transferred Out';

  @override
  String get receivedFrom => 'Received From';

  @override
  String transferredTo(Object sender, Object receiver) {
    return '$sender transferred to $receiver';
  }

  @override
  String receivedFromName(Object receiver, Object sender) {
    return '$receiver received from $sender';
  }

  @override
  String get transferFailed => 'Failed to record transfer';

  @override
  String get recordPurchase => 'Record Purchase';

  @override
  String get purchase => 'Purchase';

  @override
  String get coffeePurchase => 'Coffee Purchase';

  @override
  String get transactionCompletedSuccessfully =>
      'Transaction completed successfully';

  @override
  String get profileUpdatedSuccessfully => 'Profile updated successfully';

  @override
  String get workerDeletedSuccessfully => 'Collector deleted successfully';

  @override
  String get workerSavedSuccessfully => 'Collector saved successfully';

  @override
  String get backupSuccessful => 'Backup Successful';

  @override
  String get insufficientBalance => 'Insufficient balance';

  @override
  String get workerNotFound => 'Collector not found';

  @override
  String get notificationSent => 'Notification sent';

  @override
  String get errorOccurred => 'An error occurred';

  @override
  String get pleaseWait => 'Please wait...';

  @override
  String get loading => 'Loading...';

  @override
  String get noTransactionsYet => 'No transactions yet';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get endOfTransactions => '— End of transactions —';

  @override
  String get companyName => 'Company Name';

  @override
  String get companyAddress => 'Address';

  @override
  String get companyPhone => 'Phone';

  @override
  String maxDistributionLimit(Object currency) {
    return 'Max Distribution Limit ($currency)';
  }

  @override
  String get topBuyer => 'Top Buyer';

  @override
  String get commission => 'Commission';

  @override
  String get purchased => 'Purchased';

  @override
  String get purchasesByType => 'Coffee Purchases by Type';

  @override
  String get quickNotes => 'Quick Notes';

  @override
  String get cashPayment => 'Cash payment';

  @override
  String get creditToCollect => 'Credit - to collect';

  @override
  String get qualityGood => 'Quality: Good';

  @override
  String get qualityAverage => 'Quality: Average';

  @override
  String get notes => 'Notes';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get login => 'Login';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get addWorker => 'Add Collector';

  @override
  String get editWorker => 'Edit Collector';

  @override
  String get workerName => 'Collector Name';

  @override
  String get workerPhone => 'Phone Number';

  @override
  String get workerRole => 'Role';

  @override
  String get yearsOfExperience => 'Years of Experience';

  @override
  String get createLoginAccount => 'Create Login Account';

  @override
  String get todayTopBuyer => 'Today\'s Top Buyer';

  @override
  String get avgPriceToday => 'Average Price Today';

  @override
  String get commissionPaidToday => 'Commission Paid Today';

  @override
  String get lowBalanceAlert => 'Low Balance Alert';

  @override
  String get moneyReceived => 'Money Received';

  @override
  String get purchaseRecorded => 'Purchase Recorded';

  @override
  String get viewSystemLogs => 'View system activity logs';

  @override
  String get backupExportClear => 'Backup, Export, Clear Cache';

  @override
  String get onlyViewersCanEdit =>
      'Business settings can only be edited by viewers (owners).';

  @override
  String showingTransactions(Object count, Object total) {
    return 'Showing $count of $total transactions';
  }

  @override
  String remainingItems(Object count) {
    return '$count remaining';
  }

  @override
  String showingAllTransactions(Object count) {
    return 'Showing all $count transactions';
  }

  @override
  String get enterMessage => 'Please enter a message';

  @override
  String errorSendingPing(Object error) {
    return 'Error sending ping: $error';
  }

  @override
  String get workerAccountCreated => 'Collector Account Created!';

  @override
  String loginCredentialsFor(Object name) {
    return 'Login credentials for $name:';
  }

  @override
  String get sendCredentialsToWorker =>
      'Send these credentials to the collector:';

  @override
  String get welcomeToCofiz => 'Welcome to Cofiz!';

  @override
  String get credentialsCopied => 'Credentials copied to clipboard';

  @override
  String get couldNotOpenSms => 'Could not open SMS app';

  @override
  String get downloadAppMessage =>
      'Download the app and login to start tracking your sales.';

  @override
  String get allActions => 'All Actions';

  @override
  String get accessDenied => 'Access Denied';

  @override
  String get adminAuditLogsOnly => 'Only administrators can view audit logs';

  @override
  String filtering(Object filter) {
    return 'Filtering: $filter';
  }

  @override
  String get clear => 'Clear';

  @override
  String get errorLoadingLogs => 'Error loading logs';

  @override
  String get noAuditLogs => 'No Audit Logs';

  @override
  String get activityLogsWillAppear => 'Activity logs will appear here';

  @override
  String get signInToWorkspace => 'Sign in to your workspace.';

  @override
  String get thisFieldRequired => 'This field is required';

  @override
  String get validEmailRequired => 'Please enter a valid email';

  @override
  String get passwordLengthError => 'Password must be at least 6 characters';

  @override
  String get signIn => 'Sign In';

  @override
  String passwordResetLinkSent(Object email) {
    return 'Password reset link sent to $email';
  }

  @override
  String get failedToSendResetLink => 'Failed to send reset link';

  @override
  String get sendResetLink => 'Send Reset Link';

  @override
  String get enterEmailResetPassword =>
      'Enter your email address and we\'ll send you a link to reset your password.';

  @override
  String get pingAllWorkers => 'Ping All Collectors';

  @override
  String get messageToAllWorkers => 'Message to all collectors';

  @override
  String get announcement => 'Announcement';

  @override
  String get admin => 'Admin';

  @override
  String get notificationSentToAll => 'Notification sent to all collectors';

  @override
  String get markAllAsRead => 'Mark all as read';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(Object minutes) {
    return '${minutes}m ago';
  }

  @override
  String hoursAgo(Object hours) {
    return '${hours}h ago';
  }

  @override
  String daysAgo(Object days) {
    return '${days}d ago';
  }

  @override
  String get last7Days => 'Last 7 Days';

  @override
  String get thisMonth => 'This Month';

  @override
  String get allTime => 'All Time';

  @override
  String get chooseDate => 'Choose Date';

  @override
  String get preparingPdfReport => 'Preparing PDF Report...';

  @override
  String get noTransactionsFound => 'No transactions found';

  @override
  String get records => 'records';

  @override
  String get business => 'Business';

  @override
  String get manageAreas => 'Manage Areas';

  @override
  String get purchaseLocations => 'Purchase locations';

  @override
  String get general => 'General';

  @override
  String get preferences => 'Preferences';

  @override
  String get data => 'Data';

  @override
  String get backupExportClearCache => 'Backup, Export, Clear Cache';

  @override
  String get viewSystemActivityLogs => 'View system activity logs';

  @override
  String get app => 'App';

  @override
  String version(Object version) {
    return 'Version $version';
  }

  @override
  String passwordResetEmailSent(Object email) {
    return 'Password reset email sent to $email';
  }

  @override
  String failedToSendResetEmail(Object error) {
    return 'Failed to send reset email: $error';
  }

  @override
  String get changePasswordDialogTitle => 'Change Password';

  @override
  String get changePasswordDialogContent =>
      'To change your password, we will send a password reset link to your email address. Do you want to proceed?';

  @override
  String get updateFailed => 'Update failed';

  @override
  String get fullName => 'Full Name';

  @override
  String get enterYourName => 'Enter your name';

  @override
  String get pleaseEnterYourName => 'Please enter your name';

  @override
  String get emailAddress => 'Email Address';

  @override
  String get emailCannotBeChanged => 'Email cannot be changed';

  @override
  String get emailNotifications => 'Email Notifications';

  @override
  String get receiveUpdatesViaEmail => 'Receive updates via email';

  @override
  String get pushNotifications => 'Push Notifications';

  @override
  String get receiveInstantAlerts => 'Receive instant alerts on your device';

  @override
  String get verifyEmail => 'Verify email';

  @override
  String get emailVerified => 'Verified';

  @override
  String get verify => 'Verify';

  @override
  String get resendCode => 'Resend code';

  @override
  String get enterVerificationCode => 'Enter verification code';

  @override
  String get codeSentToEmail => 'Verification code sent to your email';

  @override
  String get emailVerifiedSuccess => 'Email verified';

  @override
  String get codeSendFailed => 'Could not send code. Try again.';

  @override
  String get invalidCode => 'Invalid code. Try again.';

  @override
  String get codeExpired => 'Code expired. Tap to resend.';

  @override
  String get tooManyAttempts => 'Too many attempts - resend code';

  @override
  String attemptsRemaining(Object count) {
    return '$count attempts remaining';
  }

  @override
  String get businessSettingsSaved => 'Business settings saved successfully';

  @override
  String errorSavingSettings(Object error) {
    return 'Error saving settings: $error';
  }

  @override
  String get companyInformation => 'Company Information';

  @override
  String get address => 'Address';

  @override
  String get phone => 'Phone';

  @override
  String get businessLimits => 'Business Limits';

  @override
  String get required => 'Required';

  @override
  String get invalidNumber => 'Invalid number';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get legal => 'Legal';

  @override
  String get support => 'Support';

  @override
  String get contactSupport => 'Contact Support';

  @override
  String get contactDetails => 'Contact Details';

  @override
  String get visitWebsite => 'Visit Website';

  @override
  String get copyright => '© 2026 Cofiz app. All rights reserved.';

  @override
  String get areaAlreadyExists => 'Area already exists';

  @override
  String areaAdded(Object name) {
    return 'Area \"$name\" added';
  }

  @override
  String get deleteArea => 'Delete Area';

  @override
  String deleteAreaConfirmation(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String areaDeleted(Object name) {
    return 'Area \"$name\" deleted';
  }

  @override
  String get editArea => 'Edit Area';

  @override
  String get areaName => 'Area Name';

  @override
  String areaRenamed(Object name) {
    return 'Area renamed to \"$name\"';
  }

  @override
  String get enterNewAreaName => 'Enter new area name...';

  @override
  String get noAreasYet => 'No areas yet';

  @override
  String get addYourFirstArea => 'Add your first area above';

  @override
  String get defaultArea => 'Default area';

  @override
  String dataExportedTo(Object path) {
    return 'Data exported to:\n\n$path\n\nYou can access this file from your device file manager.';
  }

  @override
  String exportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String get clearCache => 'Clear Cache?';

  @override
  String get clearCacheConfirmation =>
      'This will clear local preferences (theme, settings, last login). It will NOT delete collectors or transactions.\n\nAre you sure?';

  @override
  String get cacheCleared =>
      'Cache cleared. Please restart app for full effect.';

  @override
  String get backupAndExport => 'Backup & Export';

  @override
  String get exportDataJson => 'Export Data (JSON)';

  @override
  String get exportDataSubtitle =>
      'Save a full backup of all collectors and transactions to your device.';

  @override
  String get storage => 'Storage';

  @override
  String get clearAppCache => 'Clear App Cache';

  @override
  String get clearAppCacheSubtitle =>
      'Reset local preferences and temporary files.';

  @override
  String get failedToDeleteWorker => 'Failed to delete collector';

  @override
  String get deleteTransactionTitle => 'Delete Transaction';

  @override
  String deleteTransactionConfirmation(Object amount) {
    return 'Are you sure you want to delete this transaction of $amount? The collector\'s balance will be updated.';
  }

  @override
  String get transactionDeleted => 'Transaction deleted';

  @override
  String get failedToDeleteTransaction => 'Failed to delete transaction';

  @override
  String get distribute => 'Distribute';

  @override
  String get statistics => 'Statistics';

  @override
  String get performance => 'Performance';

  @override
  String get transactionsWillAppearHere => 'Transactions will appear here';

  @override
  String get call => 'Call';

  @override
  String get message => 'Message';

  @override
  String couldNotMakeCall(Object error) {
    return 'Could not make call: $error';
  }

  @override
  String couldNotSendSMS(Object error) {
    return 'Could not send SMS: $error';
  }

  @override
  String yearsExperience(Object years) {
    return '$years years experience';
  }

  @override
  String get emailRequiredForLogin =>
      'Email is required to create a login account';

  @override
  String workerSavedAccountFailed(Object error) {
    return 'Collector saved, but login account failed: $error';
  }

  @override
  String get workerUpdatedSuccessfully => 'Collector updated successfully';

  @override
  String get workerAddedSuccessfully => 'Collector added successfully';

  @override
  String get failedToSaveWorker => 'Failed to save collector';

  @override
  String get nameIsRequired => 'Name is required';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get phoneNumberIsRequired => 'Phone number is required';

  @override
  String get commissionRateIsRequired => 'Commission rate is required';

  @override
  String get enterValidNumber => 'Enter a valid number';

  @override
  String get emailRequiredLogin => 'Email (Required for login)';

  @override
  String get emailOptional => 'Email (Optional)';

  @override
  String get enterValidEmail => 'Please enter a valid email address';

  @override
  String get allowWorkerLogin => 'Allow this collector to login to the app';

  @override
  String years(Object count) {
    return '$count years';
  }

  @override
  String get status => 'Status';

  @override
  String get performanceRating => 'Performance Rating';

  @override
  String get filterWorkers => 'Filter Collectors';

  @override
  String get tryAdjustingSearch => 'Try adjusting your search';

  @override
  String get tapToAddWorker => 'Tap + to add your first collector';

  @override
  String get returnMoneyTitle => 'Return Money';

  @override
  String get transaction => 'Transaction';

  @override
  String errorPickingImage(Object error) {
    return 'Error picking image: $error';
  }

  @override
  String get failedToUploadReceipt => 'Failed to upload receipt';

  @override
  String get receipt => 'Receipt';

  @override
  String get receiptDownloaded => 'Receipt downloaded';

  @override
  String get failedToDownloadReceipt => 'Failed to download receipt';

  @override
  String get transactionCompleted => 'Transaction completed successfully';

  @override
  String get failedToComplete => 'Failed to complete transaction';

  @override
  String amountWithCurrency(Object currency) {
    return 'Amount ($currency)';
  }

  @override
  String get amountIsRequired => 'Amount is required';

  @override
  String get invalidAmount => 'Invalid amount';

  @override
  String get selectCoffeeType => 'Please select a coffee type';

  @override
  String get weightKg => 'Weight (Kg)';

  @override
  String get totalCostCalculated => 'Total Cost (Calculated)';

  @override
  String get notesOptional => 'Notes (Optional)';

  @override
  String get addNotesHere => 'Add any notes here...';

  @override
  String get receiptSelected => 'Receipt Selected';

  @override
  String get addReceiptPhoto => 'Add Receipt Photo';

  @override
  String get workerDataNotFound => 'Collector data not found';

  @override
  String get refresh => 'Refresh';

  @override
  String get navHome => 'Home';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get recentActivity => 'Recent Activity';

  @override
  String get lowBalanceWarning => 'Low balance - please return funds';

  @override
  String get balanceGood => 'Balance looks good';

  @override
  String get recordReturn => 'Record Return';

  @override
  String offlineSyncPending(Object count) {
    return 'Offline • $count pending';
  }

  @override
  String get youAreOffline => 'You are offline';

  @override
  String yrs(Object count) {
    return '$count yrs';
  }

  @override
  String get low => 'Low';

  @override
  String get recordCoffeePurchaseTitle => 'Record Coffee Purchase';

  @override
  String get recordCoffeePurchaseSubtitle =>
      'Record coffee purchased from farmers';

  @override
  String get coffeeTypeLabel => 'Coffee Type *';

  @override
  String get quantityKgLabel => 'Quantity (Kg) *';

  @override
  String pricePerKgLabel(Object currency) {
    return 'Price/Kg ($currency) *';
  }

  @override
  String get yourCommission => 'Your Commission:';

  @override
  String commissionRateInfo(Object currency, Object rate) {
    return 'Rate: $currency $rate per Kg';
  }

  @override
  String get purchaseLocation => 'Purchase Location';

  @override
  String get noAreasConfigured => 'No areas configured. Add areas in Settings.';

  @override
  String get placeLocationLabel => 'Place / Location (if not in list above)';

  @override
  String get notesDetailsLabel => 'Notes (details...)';

  @override
  String availableBalance(Object amount, Object currency) {
    return 'Available: $currency $amount';
  }

  @override
  String get insufficient => ' — Insufficient!';

  @override
  String get insufficientBalanceForPurchase =>
      'Insufficient balance for this purchase';

  @override
  String locationPrefix(Object place) {
    return 'Location: $place';
  }

  @override
  String purchaseRecordedSuccess(Object commission, Object currency) {
    return 'Purchase recorded! Commission: $currency $commission';
  }

  @override
  String get failedToRecordPurchase => 'Failed to record purchase';

  @override
  String get recordReturnSubtitle =>
      'Record money you are returning to the admin';

  @override
  String amountLabel(Object currency) {
    return 'Amount ($currency)';
  }

  @override
  String get pleaseEnterAmount => 'Please enter an amount';

  @override
  String get pleaseEnterValidAmount => 'Please enter a valid amount';

  @override
  String get amountExceedsBalance => 'Amount exceeds your current balance';

  @override
  String currentBalanceInfo(Object balance, Object currency) {
    return 'Current balance: $currency $balance';
  }

  @override
  String get returnRecordedSuccess => 'Return recorded successfully!';

  @override
  String get failedToRecordReturn => 'Failed to record return';

  @override
  String get expenseRecorded => 'Expense recorded successfully';

  @override
  String get incomeRecorded => 'Income recorded successfully';

  @override
  String get editIncome => 'Edit Income';

  @override
  String get editExpense => 'Edit Expense';

  @override
  String get incomeDeleted => 'Income deleted';

  @override
  String get expenseDeleted => 'Expense deleted';

  @override
  String get failedToDeleteIncome => 'Failed to delete income';

  @override
  String get failedToDeleteExpense => 'Failed to delete expense';

  @override
  String get deleteIncomeTitle => 'Delete Income';

  @override
  String deleteIncomeConfirmation(Object amount) {
    return 'Are you sure you want to delete this income of $amount?';
  }

  @override
  String get deleteExpenseTitle => 'Delete Expense';

  @override
  String deleteExpenseConfirmation(Object amount) {
    return 'Are you sure you want to delete this expense of $amount?';
  }

  @override
  String get moneyReturnedTitle => 'Money Returned';

  @override
  String get coffeePurchaseTitle => 'Coffee Purchase';

  @override
  String get kg => 'Kg';

  @override
  String get pingMessageHint => 'e.g. Please submit your daily report';

  @override
  String get copy => 'Copy';

  @override
  String get loginCredentialsTitle => 'Cofiz Login Credentials';

  @override
  String pingWorkerTitle(Object name) {
    return 'Ping $name';
  }

  @override
  String get messageFromAdmin => 'Message from Admin';

  @override
  String notificationSentToUser(Object name) {
    return 'Notification sent to $name';
  }

  @override
  String get today => 'Today';

  @override
  String get errorGeneratingReport => 'Error generating report';

  @override
  String get remaining => 'remaining';

  @override
  String get pingWorker => 'Ping';

  @override
  String get welcome => 'Welcome';

  @override
  String get addCategory => 'Add Category';

  @override
  String get addExpense => 'Add Expense';

  @override
  String get addIncome => 'Add Income';

  @override
  String get categoryName => 'Category Name';

  @override
  String get collector => 'Collector';

  @override
  String get collectors => 'Collectors';

  @override
  String get companyIncome => 'Income';

  @override
  String get defaultCategoriesCannotBeDeleted =>
      'Default categories cannot be deleted';

  @override
  String get expenseDescription => 'Description';

  @override
  String get expenseRecords => 'Expense Records';

  @override
  String get expenses => 'Expenses';

  @override
  String get incomeBreakdown => 'Income Breakdown';

  @override
  String get incomeDescription => 'Description';

  @override
  String get incomeRecords => 'Income Records';

  @override
  String get investment => 'Investment';

  @override
  String get investmentIncome => 'Investment Income';

  @override
  String get latestTransactions => 'Latest Transactions';

  @override
  String get manageExpenseCategories => 'Manage Expense Categories';

  @override
  String get manageSaleCategories => 'Manage Sale Categories';

  @override
  String get manualSales => 'Manual Sales';

  @override
  String get moneyIn => 'Cash In';

  @override
  String get moneyOut => 'Cash Out';

  @override
  String get myInvestments => 'My Investments';

  @override
  String get noViewersFound => 'No viewers found';

  @override
  String get recordExpense => 'Record Expense';

  @override
  String get recordInvestment => 'Record Investment';

  @override
  String get recordSale => 'Record Sale';

  @override
  String get recordedBy => 'Recorded by';

  @override
  String get sale => 'Sale';

  @override
  String get salesIncome => 'Sales Income';

  @override
  String get selectExpenseCategory => 'Select Expense Category';

  @override
  String get selectSaleCategory => 'Select Category';

  @override
  String get selectViewer => 'Select Viewer';

  @override
  String get selectSource => 'Select Source';

  @override
  String get totalExpenses => 'Total Expenses';

  @override
  String get totalIncome => 'Total Income';

  @override
  String get viewer => 'Viewer';

  @override
  String get viewerInvestment => 'Investment';

  @override
  String get pending => 'Pending';

  @override
  String get pendingApprovals => 'Pending Approvals';

  @override
  String get approveAll => 'Confirm All';

  @override
  String get noPendingApprovals => 'No entries waiting for confirmation';

  @override
  String get allConfirmed => 'All entries confirmed';

  @override
  String get entryConfirmed => 'Entry confirmed';

  @override
  String get editTransaction => 'Edit Transaction';

  @override
  String get recordTransactions => 'Record Transactions';

  @override
  String get selectCollector => 'Select Collector';

  @override
  String get searchCollector => 'Search collectors';

  @override
  String get noCollectorsFound => 'No collectors found';

  @override
  String get enterSourceName => 'Type the source name';

  @override
  String get filterByDate => 'Filter by date';

  @override
  String get cashFlow => 'Cash flow';

  @override
  String get neutral => 'Neutral';

  @override
  String get tapAgainToExit => 'Tap back again to exit';

  @override
  String get lockedEntry => 'Locked';

  @override
  String get lockedReasonTitle => 'Admin override required';

  @override
  String lockedReasonMessage(Object action) {
    return 'This entry is older than 7 days and is locked. Enter a reason to $action it.';
  }

  @override
  String get reasonLabel => 'Reason';

  @override
  String get reasonHint => 'Why are you changing this entry?';

  @override
  String get reasonRequired =>
      'A reason is required to override a locked entry.';

  @override
  String get transactionUpdated => 'Transaction updated';

  @override
  String get botOptInBannerBody =>
      'Tap to open Telegram and press Start, then return to the app.';

  @override
  String get botOptInBannerTitle => 'One-time setup';

  @override
  String get enterPhoneNumber => 'Phone number';

  @override
  String get enterSixDigitCode => 'Enter 6-digit code';

  @override
  String get invalidPhoneNumber =>
      'Enter a valid phone number (e.g. +251911234567)';

  @override
  String get providerTelegram => 'Telegram';

  @override
  String get providerWhatsapp => 'WhatsApp';

  @override
  String get sendCode => 'Send code';

  @override
  String get createPinTitle => 'Create your PIN';

  @override
  String get confirmPinTitle => 'Confirm your PIN';

  @override
  String get pinMismatch => 'PINs do not match';

  @override
  String get pinLockTitle => 'Enter PIN';

  @override
  String get pinForgot => 'Forgot PIN?';

  @override
  String get pinUseBiometric => 'Use fingerprint';

  @override
  String get pinIncorrect => 'Incorrect PIN';

  @override
  String get pinTooMany => 'Too many attempts. Sign in again.';

  @override
  String get pinWeak => 'PIN is too weak — choose a less predictable code';

  @override
  String get pinLock => 'PIN lock';

  @override
  String get pinLockSubtitle => 'Protect the app with a 6-digit PIN';

  @override
  String get setPin => 'Set PIN';

  @override
  String get changePin => 'Change PIN';

  @override
  String get removePin => 'Remove PIN';

  @override
  String get lockNow => 'Lock now';

  @override
  String get lockAfter2Min => 'Locks after 2 minutes of inactivity';

  @override
  String get pinSaved => 'PIN saved';

  @override
  String get pinRemoved => 'PIN removed';

  @override
  String get confirmRemovePin => 'Remove PIN?';

  @override
  String get confirmRemovePinBody =>
      'Anyone with access to this device will be able to open the app without a PIN.';

  @override
  String cooldownWait(Object seconds) {
    return 'Wait ${seconds}s before retry';
  }
}
