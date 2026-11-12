extension LanguageSample {
  static let objectiveC = LanguageSample(
    language: "Objective-C", fileName: "Example.m",
    annotated: ###"""
      «k:#import» <Foundation/Foundation.h>

      «k:@interface» Greeter : NSObject
      «k:@property» (nonatomic, copy, «k:nullable») NSString *name;
      «k:@end»

      «k:@implementation» Greeter
      - («k:instancetype»)init {
        «k:self» = [«k:super» init];
        «k:if» («k:self») { _name = «s:@"Ada // not a comment"»; } «c:/* done */»
        «k:return» «k:self»;
      }
      - («k:BOOL»)isReady { «k:return» «k:YES» && «s:'abcd'» != «n:0x10»; }
      «k:@end»
      """###)
}
