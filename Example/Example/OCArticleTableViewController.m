//
//  OCArticleTableViewController.m
//  Example
//
// Copyright 2014 Changbeom Ahn
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "OCArticleTableViewController.h"
#import <OpenClien/OpenClien.h>
#import "OCArticleTableViewCell.h"
#import "OCWebViewController.h"
#import "OCComposeViewController.h"
#import <SDWebImage/UIImageView+WebCache.h>
#import "AFHTTPRequestOperationManager.h"
#import "UIAlertView+AFNetworking.h"
#import "OCSession.h"
#import "OCBoardTableViewController.h"

static NSString *REUSE_IDENTIFIER = @"article cell";

@interface OCArticleTableViewController ()

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIImageView *imageNameView;
@property (weak, nonatomic) IBOutlet UILabel *infoLabel;
@property (weak, nonatomic) IBOutlet UIWebView *contentView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *contentHeightConstraint;

@end

@implementation OCArticleTableViewController
{
    OCArticleParser *_parser;
    NSArray *_comments;
    OCArticleTableViewCell *_sizingCell;
    UIToolbar *_toolbar;
    UITextView *_textView;
    __weak UITextField *_memoTextField;
    NSArray *_memos;
    OCScrapParser *_scrapParser;
}

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        _parser = [[OCArticleParser alloc] init];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        _parser = [[OCArticleParser alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSDictionary *userInfo = [note userInfo];
            CGRect frame = [userInfo[UIKeyboardFrameBeginUserInfoKey] CGRectValue];
            _toolbar.frame = CGRectMake(0, frame.origin.y - _textView.bounds.size.height - 20, frame.size.width, _textView.bounds.size.height + 20);
            frame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
            NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
            UIViewAnimationOptions options = [userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue] << 16; // fixme ugly!
            [UIView animateWithDuration:duration delay:0 options:options animations:^{
                _toolbar.frame = CGRectMake(0, frame.origin.y - _textView.bounds.size.height - 20, frame.size.width, _textView.bounds.size.height + 20);
            } completion:NULL];
            
            UIEdgeInsets contentInset = self.tableView.contentInset;
            contentInset.bottom += _toolbar.frame.size.height - self.navigationController.toolbar.bounds.size.height; // fixme ugly!
            self.tableView.contentInset = contentInset;
        }];
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillHideNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            UIEdgeInsets contentInset = self.tableView.contentInset;
            contentInset.bottom -= _toolbar.frame.size.height - self.navigationController.toolbar.bounds.size.height; // fixme ugly!
            self.tableView.contentInset = contentInset;

            [_toolbar removeFromSuperview];
            self.navigationItem.leftBarButtonItem = nil;
        }];
    }
    return self;
}

- (void)dealloc
{
    _contentView.delegate = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _contentView.superview.translatesAutoresizingMaskIntoConstraints = NO;
    
    _contentView.scrollView.scrollsToTop = NO;
    _contentView.scrollView.scrollEnabled = NO;
    [_contentView.scrollView addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:NULL];
    
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _infoLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _comments.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OCArticleTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:REUSE_IDENTIFIER];
//    if (!cell) {
//        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:REUSE_IDENTIFIER];
//    }

    [self configureCell:cell forRowAtIndexPath:indexPath];
    
    if (!cell.textView.tag) {
        cell.textView.tag = 1;
        
        UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        gestureRecognizer.delegate = self;
        [cell.textView addGestureRecognizer:gestureRecognizer];
        
        cell.textView.scrollsToTop = NO;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"댓글";
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    OCComment *comment = _comments[indexPath.row];
    if (comment.deletable) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *URL = [_parser deleteURLForComment:_comments[indexPath.row]];
        NSData *data = [NSData dataWithContentsOfURL:URL];
        NSError *error;
        if ([_parser parseDeleteResult:data error:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *comments = [_comments mutableCopy];
                [comments removeObjectAtIndex:indexPath.row];
                _comments = comments;
                [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                OCAlert(error.localizedDescription);
                [self reload];
            });
        }
    });
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self configureCell:[self sizingCell] forRowAtIndexPath:indexPath];
    [self sizingCell].textView.scrollEnabled = NO; // NOTE iOS 7.0.4에서 필요 :-(
    [[self sizingCell] layoutIfNeeded];
    return [[self sizingCell].contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height + 1;
}

- (void)configureCell:(OCArticleTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    OCComment *comment = _comments[indexPath.row];
    cell.textView.text = comment.content;
    cell.textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    if (comment.imageNameURL) {
        [cell.imageNameView setImageWithURL:comment.imageNameURL];
        cell.infoLabel.text = [NSString stringWithFormat:@"님 %@", comment.date];
    } else {
        cell.infoLabel.text = [NSString stringWithFormat:@"%@ %@", comment.name, comment.date];
        cell.imageNameView.image = nil;
    }
    cell.infoLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.leftMarginConstraint.constant = comment.isNested ? 25 : 5;
}

- (OCArticleTableViewCell *)sizingCell
{
    if (!_sizingCell) {
        _sizingCell = [self.tableView dequeueReusableCellWithIdentifier:REUSE_IDENTIFIER];
    }
    return _sizingCell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self showCommentMenu:indexPath];
}

- (void)showCommentMenu:(NSIndexPath *)indexPath {
    OCComment *comment = _comments[indexPath.row];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:comment.memberId delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (comment.deletable) {
        sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"삭제"];
    }
    if (comment.editable) {
        [sheet addButtonWithTitle:@"수정"];
    }
    [sheet addButtonWithTitle:@"쪽지보내기"];
    [sheet addButtonWithTitle:@"메일보내기"];
    [sheet addButtonWithTitle:@"자기소개"];
    [sheet addButtonWithTitle:@"아이디로 검색"];
    [sheet addButtonWithTitle:@"차단하기"];
    if (comment.reportable) {
        [sheet addButtonWithTitle:@"신고"];
    }
    if (comment.repliable || comment.branch.repliable) {
        [sheet addButtonWithTitle:@"답변"];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"취소"];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    [sheet showFromRect:cell.bounds inView:cell animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != actionSheet.cancelButtonIndex) {
        if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"답변"]) {
            [self reply:self];
        } else if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"아이디로 검색"]) {
            [self performSegueWithIdentifier:@"search" sender:self];
        } else {
            // fixme
            OCAlert(@"미구현");
        }
    }
}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
    if ([identifier isEqualToString:@"reply"]) {
        if (![_parser canComment]) {
            [[OCSession defaultSession] showLoginAlertView:^(NSError *error) {
                if (error) {
                    NSLog(@"%@", error);
                    OCAlert(error.description);
                } else {
                    // fixme perform segue?
                    [self reload];
                }
            } URL:_article.URL];
            return NO;
        }
    }
    return YES;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"web"]) {
        OCWebViewController *vc = segue.destinationViewController;
        if ([sender isKindOfClass:[NSURL class]]) {
            vc.URL = sender;
        } else {
            vc.URL = _article.URL;
        }
    } else if ([segue.identifier isEqualToString:@"article"]) {
        OCArticleTableViewController *vc = segue.destinationViewController;
        vc.article = sender;
    } else if ([segue.identifier isEqualToString:@"edit"]) {
        UINavigationController *nc = segue.destinationViewController;
        OCComposeViewController *vc = nc.viewControllers[0];
        vc.URL = _parser.editURL;
    } else if ([segue.identifier isEqualToString:@"search"]) {
        OCBoardTableViewController *vc = segue.destinationViewController;
        vc.comment = _comments[[self.tableView indexPathForSelectedRow].row];
    } else {
        NSLog(@"%s segue=%@ sender=%@", __PRETTY_FUNCTION__, segue, sender);
    }
}

- (void)setArticle:(OCArticle *)article
{
    _article = article;
//    self.title = article.title;
    [self reload];
}

- (void)reload
{
    [self.refreshControl beginRefreshing];
    self.tableView.contentOffset = CGPointMake(0, -CGRectGetHeight(self.refreshControl.frame));
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData* data = [NSData dataWithContentsOfURL:_article.URL];
        if (!data) {
            // fixme
            OCAlert(@"통신 오류");
            return;
        }
        
        [_parser parse:data article:_article];

        NSArray *files = _parser.files;
        NSString *fileHTML = @"";
        if (files) {
            for (OCFile *file in files) {
                fileHTML = [fileHTML stringByAppendingFormat:@"<li>📄 <a href=\"%@\">%@</a> %@ (%d)", file.URL, file.name, file.size, file.downloadCount];
            }
        }
        
        NSArray *links = _parser.links;
        NSString *linkHTML = @"";
        if (links) {
            for (OCLink *link in links) {
                linkHTML = [linkHTML stringByAppendingFormat:@"<li>🔗 <a href=\"%@\">%@</a> (%d)", link.URL, link.text, link.hitCount];
            }
        }
        
        NSString *html = [NSString stringWithFormat:
                          @"<html><head>"\
                          "<meta name=\"viewport\" content=\"width=device-width\">"\
                          "<style>body{word-break:break-all;margin:0;"\
                          "font:-apple-system-body}"\
                          " *{max-width:100%%} #writeContents{margin:10px;display:block}</style></head>"\
                          "<script>function image_window3(s,w,h){"\
                          "go('image://'+encodeURIComponent(s))}"\
                          " function go(h){location.href=h}</script>"\
                          "<body onload=\"go('ready://'+document.height)\">"\
                          "<ul style=\"list-style-type:none;padding-left:10px;font:-apple-system-footnote\">%@%@</ul>"\
                          "%@</body></html>",
                          fileHTML,
                          linkHTML,
                          _parser.content];
        _comments = _parser.comments;
        BOOL editable = _parser.canEdit;
        dispatch_async(dispatch_get_main_queue(), ^{
            _titleLabel.text = _parser.title;
            if (_parser.imageNameURL) {
                [_imageNameView setImageWithURL:_parser.imageNameURL];
                _infoLabel.text = @"님";
            } else {
                _infoLabel.text = _parser.name;                
            }
            [_contentView loadHTMLString:html baseURL:_article.URL];
            [self.tableView reloadData];
            if (editable) {
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"수정" style:UIBarButtonItemStyleBordered target:self action:@selector(edit:)];
            }
        });
    });
}

#pragma mark - Web view delegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        OCRedirectResolver *resolver = [[OCRedirectResolver alloc] init];
        [resolver resolve:request.URL completion:^(NSURL *url) {
            if ([url isClienURL]) {
                [self performSegueWithIdentifier:@"article" sender:[url article]];
            } else {
                [self performSegueWithIdentifier:@"web" sender:url];
            }
        }];
        return NO;
    }
    if ([request.URL.scheme isEqualToString:@"ready"]) {
        NSLog(@"ready");
//        [self resizeTableHeaderView:[request.URL.host intValue]];
        [self.refreshControl endRefreshing];
        return NO;
    }
    if ([request.URL.scheme isEqualToString:@"image"]) {
        [self performSegueWithIdentifier:@"web" sender:[NSURL URLWithString:request.URL.host]];
        return NO;
    }
    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
//    [self resizeTableHeaderView:webView.scrollView.contentSize.height];
}

- (void)resizeTableHeaderView:(int)height
{
    _contentHeightConstraint.constant = height;
    
    [_contentView.superview layoutIfNeeded];

    UIView *header = self.tableView.tableHeaderView;
    CGRect frame = header.frame;
    frame.size.height = _contentView.superview.frame.size.height;
    header.frame = frame;
    
    self.tableView.tableHeaderView = header;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSLog(@"%@", error);
}

- (IBAction)scrap:(id)sender {
    if (_parser.scrapURL) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:nil delegate:self cancelButtonTitle:@"취소" otherButtonTitles:@"확인", nil];
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        _memoTextField = [alert textFieldAtIndex:0];
        _memoTextField.placeholder = @"메모";
        UIToolbar *toolbar = [[UIToolbar alloc] init];
        UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"입력", @"선택"]];
        segmentedControl.selectedSegmentIndex = 0;
        [segmentedControl addTarget:self action:@selector(changeMemoInputView:) forControlEvents:UIControlEventValueChanged];
        UIBarButtonItem *segmentedItem = [[UIBarButtonItem alloc] initWithCustomView:segmentedControl];
        toolbar.items = @[segmentedItem];
        [toolbar sizeToFit];
        _memoTextField.inputAccessoryView = toolbar;
        [alert show];
    } else {
        [[OCSession defaultSession] showLoginAlertView:^(NSError *error) {
            if (error) {
                NSLog(@"%@", error);
                OCAlert(error.userInfo[NSLocalizedDescriptionKey]);
            } else {
                [self reload];
            }
        } URL:_article.URL];
    }
}

#pragma mark - Alert view delegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[self scrapParser] prepareSubmitWithMemo:_memoTextField.text block:^(NSURL *URL, NSDictionary *parameters) {
                AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
                manager.responseSerializer = [AFHTTPResponseSerializer serializer];
                [manager POST:URL.absoluteString parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
                    [[self scrapParser] parseSubmitResponse:responseObject];
                    // fixme
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    NSLog(@"%@", error);
                    OCAlert([error localizedDescription]);
                }];
            }];
        });
    }
}

- (void)changeMemoInputView:(id)sender {
    [_memoTextField resignFirstResponder];
    UISegmentedControl *segmentedControl = sender;
    if (segmentedControl.selectedSegmentIndex == 0) {
        _memoTextField.inputView = nil;
    } else {
        UIPickerView *picker = [[UIPickerView alloc] init];
        picker.dataSource = self;
        picker.delegate = self;
        _memoTextField.inputView = picker;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            _memos = [self scrapParser].memos;
            dispatch_async(dispatch_get_main_queue(), ^{
                [(UIPickerView *) _memoTextField.inputView reloadAllComponents];
            });
        });
    }
    [_memoTextField becomeFirstResponder];
}

- (OCScrapParser *)scrapParser {
    if (!_scrapParser) {
        _scrapParser = [[OCScrapParser alloc] initWithURL:_parser.scrapURL];
        NSData *data = [NSData dataWithContentsOfURL:_parser.scrapURL]; // NOTE will block here!
        [_scrapParser parse:data];
    }
    return _scrapParser;
}

#pragma mark - Picker view data source

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return [_memos count];
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return _memos[row];
}

#pragma mark - Picker view delegate

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    _memoTextField.text = _memos[row];
}

#pragma mark - Text view delegate

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
    [self performSegueWithIdentifier:@"web" sender:URL];
    return NO;
}

- (void)textViewDidChange:(UITextView *)textView
{
//    CGSize size = [textView sizeThatFits:textView.bounds.size];
    // fixme 댓글 입력창 높이 조절
}

- (void)tap:(UIGestureRecognizer *)gestureRecognizer
{
//    NSLog(@"%s: %@", __PRETTY_FUNCTION__, gestureRecognizer);
    CGPoint point = [gestureRecognizer locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    
    [self showCommentMenu:indexPath];
}

//- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
//{
//    NSLog(@"%s", __PRETTY_FUNCTION__);
//    CGPoint point = [touch locationInView:self.tableView];
//    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
//    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
//    return YES;
//}

- (IBAction)reply:(id)sender {
    _toolbar = [[UIToolbar alloc] init];
    _textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 200, 90)];
    _textView.delegate = self;
    _textView.scrollsToTop = NO;
    _textView.text = [[self commentToReply].name stringByAppendingFormat:@"님\n"];
    UIBarButtonItem *textViewItem = [[UIBarButtonItem alloc] initWithCustomView:_textView];
    UIBarButtonItem *submitItem = [[UIBarButtonItem alloc] initWithTitle:@"댓글쓰기" style:UIBarButtonItemStylePlain target:self action:@selector(submit)];
    _toolbar.items = @[textViewItem, submitItem];
    [_toolbar sizeToFit];
    [self.navigationController.view addSubview:_toolbar];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:_textView action:@selector(resignFirstResponder)];
    [_textView becomeFirstResponder];
}

- (void)submit
{
    OCComment *comment = [self commentToReply];
    OCCommentParser *parser = [[OCCommentParser alloc] init];
    if (comment) {
        [parser prepareWithContent:_textView.text comment:comment block:^(NSURL *URL, NSDictionary *parameters) {
            [self submitTo:URL parameters:parameters parser:parser];
        }];
    } else {
        NSDictionary *parameters = [parser parametersForArticle:_article content:_textView.text];
        [self submitTo:[OCCommentParser URL] parameters:parameters parser:parser];
    }
}

- (OCComment *)commentToReply {
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    if (indexPath) {
        return _comments[indexPath.row];
    } else {
        return nil;
    }
}

- (void)submitTo:(NSURL *)URL parameters:(NSDictionary *)parameters parser:(OCCommentParser *)parser {
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager POST:URL.absoluteString parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSError *error;
        if ([parser parse:responseObject error:&error]) {
            [_textView resignFirstResponder];
            [self reload];
        } else {
            NSLog(@"%@", error);
            // fixme
            OCAlert(error.description);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"%@", error);
        // fixme
        OCAlert(error.description);
    }];
}

- (void)edit:sender {
    [self performSegueWithIdentifier:@"edit" sender:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    CGSize size = [change[NSKeyValueChangeNewKey] CGSizeValue];
    [self resizeTableHeaderView:size.height];
}

@end
