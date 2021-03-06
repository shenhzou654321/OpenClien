//
//  OCCommentParser.h
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
 (대)댓글 달기 결과 파서
 */
@interface OCCommentParser : NSObject

+ (NSURL *)URL;

- (NSDictionary *)parametersForArticle:(OCArticle *)article content:(NSString *)content;

- (BOOL)parse:(NSData *)data error:(NSError **)error;

/**
 대댓글 쓰기 요청 준비
 
 @param content 대댓글 내용
 @param comment 대댓글을 달 댓글
 @param block 요청에 필요한 정보를 받을 블록
 */
- (void)prepareWithContent:(NSString *)content comment:(OCComment *)comment block:(void (^)(NSURL *URL, NSDictionary *parameters))block;

@end
