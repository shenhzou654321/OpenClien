//
//  OCArticleParser.h
//  OpenClien
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

#import <Foundation/Foundation.h>

@class OCArticle;
@class OCComment;

/**
 게시판 글 페이지 HTML을 분석하여 글/댓글 정보를 가져옵니다.
 */
@interface OCArticleParser : NSObject

/**
 글 내용 HTML
 */
@property (nonatomic, readonly) NSString *content;

/**
 댓글 목록
 */
@property (nonatomic, readonly) NSArray *comments;

/**
 로그인 여부
 */
@property (nonatomic, readonly) BOOL loggedIn;

/**
 스크랩 가능
 */
@property (nonatomic, readonly) BOOL canScrap;

/**
 댓글 가능
 */
@property (readonly, nonatomic) BOOL canComment;

/**
 수정 가능
 */
@property (readonly, nonatomic) BOOL canEdit;

/**
 삭제 가능
 */
@property (readonly, nonatomic) BOOL canDelete;

/**
 글 제목
 */
@property (readonly, nonatomic) NSString *title;

/**
 글쓴이 닉네임
 */
@property (readonly, nonatomic) NSString *name;

/**
 글쓴이 이미지네임
 */
@property (readonly, nonatomic) NSURL *imageNameURL;

/**
 OCLink 배열
 */
@property (readonly, nonatomic) NSArray *links;

/**
 첨부파일
 */
@property (readonly, nonatomic) NSArray *files;

/**
 스크랩 URL
 */
@property (readonly, nonatomic) NSURL *scrapURL;

/**
 수정 URL
 */
@property (readonly, nonatomic) NSURL *editURL;

/**
 글 HTML data를 분석하여 content와 comments을 추출한다.
 
 @param data 글 HTML
 */
- (void)parse:(NSData *)data article:(OCArticle *)article;

/**
 댓글 삭제 URL을 반환한다.
 
 @param comment 삭제할 댓글
 
 @return 댓글 삭제 URL
 */
- (NSURL *)deleteURLForComment:(OCComment *)comment;

/**
 댓글 삭제 결과를 분석한다.
 
 @param data 댓글 삭제 결과 HTML
 @param error 분석중 발생한 오류

 @return 오류 없이 분석했으면 YES, 아니면 NO
 */
- (BOOL)parseDeleteResult:(NSData *)data error:(NSError **)error;

@end
