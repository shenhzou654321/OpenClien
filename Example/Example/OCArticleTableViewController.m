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

static NSString *REUSE_IDENTIFIER = @"article cell";

@interface OCArticleTableViewController ()

@end

@implementation OCArticleTableViewController
{
    UIWebView *_webView;
    OCArticleParser *_parser;
    NSArray *_comments;
    OCArticleTableViewCell *_sizingCell;
    UIToolbar *_toolbar;
    UITextView *_textView;
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
    _webView.delegate = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    _webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    _webView.delegate = self;
    _webView.scrollView.scrollsToTop = NO;
    _webView.scrollView.scrollEnabled = NO;
    self.tableView.tableHeaderView = _webView;
    
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
        
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        tapGestureRecognizer.delegate = self;
        [cell.textView addGestureRecognizer:tapGestureRecognizer];
        
        cell.textView.scrollsToTop = NO;
    }
    
    return cell;
}

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
    cell.leftMarginConstraint.constant = comment.isNested ? 15 : 5;
}

- (OCArticleTableViewCell *)sizingCell
{
    if (!_sizingCell) {
        _sizingCell = [self.tableView dequeueReusableCellWithIdentifier:REUSE_IDENTIFIER];
    }
    return _sizingCell;
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
    } else if ([segue.identifier isEqualToString:@"reply"]) {
        UINavigationController *nc = segue.destinationViewController;
        OCComposeViewController *vc = nc.viewControllers[0];
        vc.article = _article;
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
        [_parser parse:data article:_article];

        UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        NSString *fontStyle = [NSString stringWithFormat:@"font-size:%.0fpx", font.pointSize];
        
        NSString *html = [NSString stringWithFormat:
                          @"<html><head>"\
                          "<meta name=\"viewport\" content=\"width=device-width\">"\
                          "<style>body{word-break:break-all;"\
                          "%@}"\
                          " *{max-width:100%%}</style></head>"\
                          "<script>function image_window3(s,w,h){"\
                          "go('image://'+encodeURIComponent(s))}"\
                          " function go(h){location.href=h}</script>"\
                          "<body onload=\"go('ready://'+document.height)\">%@</body></html>",
                          fontStyle,
                          _parser.content];
        _comments = _parser.comments;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_webView loadHTMLString:html baseURL:_article.URL];
            [self.tableView reloadData];
        });
    });
}

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
        [self resizeWebView:[request.URL.host intValue]];
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
    [self resizeWebView:webView.scrollView.contentSize.height];
}

- (void)resizeWebView:(int)height
{
    NSLog(@"height=%d", height);
    _webView.frame = CGRectMake(0, 0, _webView.frame.size.width, height);
//    self.tableView.tableHeaderView = nil;
    self.tableView.tableHeaderView = _webView;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSLog(@"%@", error);
}

- (IBAction)scrap:(id)sender {
    if ([_parser canScrap]) {
        // fixme
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

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
    [self performSegueWithIdentifier:@"web" sender:URL];
    return NO;
}

- (void)textViewDidChange:(UITextView *)textView
{
    CGSize size = [textView sizeThatFits:textView.bounds.size];
    // fixme
}

- (void)tap:(UITapGestureRecognizer *)gestureRecognizer
{
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    CGPoint point = [touch locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    return YES;
}

- (IBAction)reply:(id)sender {
    _toolbar = [[UIToolbar alloc] init];
    _textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 200, 90)];
    _textView.delegate = self;
    _textView.scrollsToTop = NO;
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
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    NSString *url = [OCCommentParser URL].absoluteString;
    OCCommentParser *parser = [[OCCommentParser alloc] init];
    NSDictionary *parameters = [parser parametersForArticle:_article content:_textView.text];
    [manager POST:url parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
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

@end