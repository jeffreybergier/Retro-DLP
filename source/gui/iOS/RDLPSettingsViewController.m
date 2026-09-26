#import "RDLPSettingsViewController.h"
#import "RDLPUIKit.h"

@implementation RDLPSettingsViewController
- (id)initWithLibrary:(RDLPLibrary *)library;
{
  self=[super initWithStyle:UITableViewStyleGrouped]; if(!self) return nil;
  library_=[library retain]; model_=[[RDLPLibrarySections alloc] initWithLibrary:library];
  [self setTitle:@"Settings"];
  [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSettings:)] autorelease]];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:) name:RDLPLibraryDidChange object:library];
  return self;
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [alert_ setDelegate:nil]; [alert_ dismissWithClickedButtonIndex:0 animated:NO];
  [alert_ release]; [request_ release]; [sections_ release]; [model_ release]; [library_ release];
  [super dealloc];
}
- (void)viewDidLoad;
{ [super viewDidLoad]; [RDLPUIKit configureContentEdges:self]; [self refresh:nil]; }
- (void)viewWillAppear:(BOOL)animated;
{ [super viewWillAppear:animated]; [[self navigationController] setToolbarHidden:YES animated:animated]; [self refresh:nil]; }
- (void)refresh:(id)sender;
{
  (void)sender; if(![self isViewLoaded]) return;
  NSArray *sections=[model_ sectionsForScreen:RDLPScreenSettings playlist:nil video:nil collapsed:nil];
  [sections_ release]; sections_=[sections copy]; [[self tableView] reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table;
{ (void)table; return (NSInteger)[sections_ count]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{ (void)table; return (NSInteger)[[[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section;
{ (void)table; return [[sections_ objectAtIndex:(NSUInteger)section] objectForKey:@"title"]; }
- (NSDictionary *)rowAtIndex:(NSIndexPath *)index;
{ return [[[sections_ objectAtIndex:(NSUInteger)[index section]] objectForKey:@"rows"] objectAtIndex:(NSUInteger)[index row]]; }
- (BOOL)enabled:(NSString *)action;
{
  if([action isEqualToString:@"import"]) return ![library_ isBusy] && ![[library_ cookieStatus] isEqualToString:@"Imported"];
  if([action isEqualToString:@"clearCookies"]) return ![library_ isBusy] && ![[library_ cookieStatus] isEqualToString:@"Not Imported"];
  return YES;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[self rowAtIndex:index]; NSString *action=[row objectForKey:@"action"];
  BOOL subtitle=[action isEqualToString:@"custom"];
  NSString *identifier=subtitle?@"format":@"setting";
  UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:identifier];
  if(!cell) cell=[[[UITableViewCell alloc] initWithStyle:subtitle?UITableViewCellStyleSubtitle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
  [[cell textLabel] setText:[row objectForKey:@"title"]]; [[cell detailTextLabel] setText:[row objectForKey:@"detail"]];
  BOOL enabled=[self enabled:action];
  [[cell textLabel] setEnabled:enabled]; [[cell detailTextLabel] setEnabled:enabled];
  [cell setSelectionStyle:enabled?UITableViewCellSelectionStyleBlue:UITableViewCellSelectionStyleNone];
  [cell setAccessoryType:[[row objectForKey:@"checked"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone];
  return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index;
{
  NSDictionary *row=[[[self rowAtIndex:index] retain] autorelease];
  [table deselectRowAtIndexPath:index animated:YES]; [self performRow:row];
}
- (void)showAlert:(NSString *)title detail:(NSString *)detail request:(NSDictionary *)request button:(NSString *)button input:(NSString *)input;
{
  if(alert_) return;
  request_=[request copy];
  alert_=[[UIAlertView alloc] initWithTitle:title message:detail delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:button,nil];
  if(input) {
    [alert_ setAlertViewStyle:UIAlertViewStylePlainTextInput];
    UITextField *field=[alert_ textFieldAtIndex:0]; [field setText:input];
    [field setAutocapitalizationType:UITextAutocapitalizationTypeNone]; [field setAutocorrectionType:UITextAutocorrectionTypeNo];
  }
  [alert_ show];
}
- (void)performRow:(NSDictionary *)row;
{
  NSString *action=[row objectForKey:@"action"]; if(![self enabled:action]) return;
  if([action isEqualToString:@"quality"]) { [RDLPLibrary savePreferredFormat:[row objectForKey:@"format"]]; [self refresh:nil]; }
  else if([action isEqualToString:@"custom"]) [self showAlert:@"Custom Format" detail:@"Example: 18 or 136+140" request:[NSDictionary dictionaryWithObject:@"quality" forKey:@"operation"] button:@"Save" input:[RDLPLibrary preferredFormat]];
  else if([action isEqualToString:@"import"]) {
    NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
    [self requestCookieImport:[documents stringByAppendingPathComponent:@"cookies.txt"] discover:NO];
  } else if([action isEqualToString:@"clearCookies"]) [self showAlert:@"Remove imported cookies?" detail:@"Only the app’s working copy is removed. Your original export is retained." request:[NSDictionary dictionaryWithObject:@"clearCookies" forKey:@"operation"] button:@"Remove" input:nil];
  else if([action isEqualToString:@"guide"]) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/yt-dlp/yt-dlp/wiki/Extractors"]];
}
- (void)importRequest:(NSDictionary *)request;
{
  if([library_ isBusy]) return;
  if([library_ importCookies:[request objectForKey:@"path"]] && [[request objectForKey:@"discover"] boolValue]) [library_ discoverPlaylists];
}
- (BOOL)requestCookieImport:(NSString *)path discover:(BOOL)discover;
{
  if([library_ isBusy] || alert_) { [RDLPUIKit showMessage:@"Finish the current operation or dialog before importing cookies."]; return NO; }
  NSDictionary *request=[NSDictionary dictionaryWithObjectsAndKeys:@"import",@"operation",path,@"path",[NSNumber numberWithBool:discover],@"discover",nil];
  if(![[library_ cookieStatus] isEqualToString:@"Not Imported"])
    [self showAlert:discover?@"Replace cookies and load playlists?":@"Replace imported cookies?" detail:@"Replace the working cookie copy. Your original export is retained." request:request button:discover?@"Replace and Load":@"Replace" input:nil];
  else if([[NSFileManager defaultManager] fileExistsAtPath:path]) [self importRequest:request];
  else { [RDLPUIKit showMessage:@"Copy cookies.txt into RetroDLP with iTunes File Sharing, or open your exported text file in RetroDLP. Then use Import Cookies again."]; return NO; }
  return YES;
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index;
{
  if(alert!=alert_) return;
  NSDictionary *request=[[request_ retain] autorelease];
  NSString *text=[alert alertViewStyle]==UIAlertViewStylePlainTextInput?[[[[alert textFieldAtIndex:0] text] copy] autorelease]:nil;
  [alert_ setDelegate:nil]; [alert_ release]; alert_=nil; [request_ release]; request_=nil;
  if(index==0) return;
  NSString *operation=[request objectForKey:@"operation"];
  if([operation isEqualToString:@"quality"]) {
    if(![RDLPLibrary savePreferredFormat:text]) [RDLPUIKit showMessage:@"Enter an exact format such as 18 or 136+140."];
  } else if([operation isEqualToString:@"clearCookies"] && [self enabled:@"clearCookies"]) [library_ clearCookies];
  else if([operation isEqualToString:@"import"]) [self importRequest:request];
  [self refresh:nil];
}
- (void)dismissSettings:(id)sender;
{ (void)sender; [[self navigationController] dismissViewControllerAnimated:YES completion:nil]; }
@end
