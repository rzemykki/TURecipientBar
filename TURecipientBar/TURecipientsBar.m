//
//  TURecipientsBar.m
//  ThinkSocial
//
//  Created by David Beck on 10/23/12.
//  Copyright (c) 2012 ThinkUltimate. All rights reserved.
//

#import "TURecipientsBar.h"

#import <QuartzCore/QuartzCore.h>


#define TURecipientsLineHeight 43.0
#define TURecipientsPlaceholder @"\u200B"

void *TURecipientsSelectionContext = &TURecipientsSelectionContext;


@implementation TURecipientsBar
{
	UILabel *_toLabel;
	UIButton *_addButton;
	UILabel *_placeholderLabel;
    UIView *_summaryContainerView;
    CAGradientLayer *_summaryGradientMaskLayer;
    
	UIView *_lineView;
	NSArray *_updatingConstraints; // NSLayoutConstraint
    NSArray *_addButtonHiddenConstraints; // NSLayoutConstraint
	
	NSMutableArray *_recipients; // <TURecipient>
	NSMutableArray *_recipientViews; // UIButton
	CGSize _lastKnownSize;
	id<TURecipient>_selectedRecipient;
    BOOL _needsRecipientLayout;
    
    // UIAppearance
    NSMutableDictionary *_recipientBackgroundImages; // [@(UIControlState)] UIImage
    NSMutableDictionary *_recipientTitleTextAttributes; // [@(UIControlState)] NSDictionary(text attributes dictionary)
    
}

#pragma mark - Properties

@synthesize labelTextAttributes = _labelTextAttributes;


- (void)setPlaceholder:(NSString *)placeholder
{
    _placeholder = placeholder;
    
    [self _updateSummary];
}

- (NSArray *)recipients
{
	return [_recipients copy];
}

- (void)addRecipient:(id<TURecipient>)recipient
{
	NSIndexSet *changedIndex = [NSIndexSet indexSetWithIndex:_recipients.count];
	
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:changedIndex forKey:@"recipients"];
	[_recipients addObject:[(id)recipient copy]];
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:changedIndex forKey:@"recipients"];
	
	
	UIButton *recipientView = [UIButton buttonWithType:UIButtonTypeCustom];
    
	recipientView.adjustsImageWhenHighlighted = NO;
	recipientView.contentEdgeInsets = _recipientContentEdgeInsets;
    
    
	[recipientView setBackgroundImage:[self recipientBackgroundImageForState:UIControlStateNormal]
                             forState:UIControlStateNormal];
    [recipientView setAttributedTitle:[[NSAttributedString alloc] initWithString:recipient.recipientTitle attributes:[self recipientTitleTextAttributesForState:UIControlStateNormal]]
                             forState:UIControlStateNormal];
    
	[recipientView setBackgroundImage:[self recipientBackgroundImageForState:UIControlStateHighlighted]
							 forState:UIControlStateHighlighted];
    [recipientView setAttributedTitle:[[NSAttributedString alloc] initWithString:recipient.recipientTitle attributes:[self recipientTitleTextAttributesForState:UIControlStateHighlighted]]
                             forState:UIControlStateHighlighted];
    
	[recipientView setBackgroundImage:[self recipientBackgroundImageForState:UIControlStateSelected]
							 forState:UIControlStateSelected];
    [recipientView setAttributedTitle:[[NSAttributedString alloc] initWithString:recipient.recipientTitle attributes:[self recipientTitleTextAttributesForState:UIControlStateSelected]]
                             forState:UIControlStateSelected];
    
    
	[recipientView addTarget:self action:@selector(selectRecipientButton:) forControlEvents:UIControlEventTouchUpInside];
    
    
	[self addSubview:recipientView];
    
    [self _setNeedsRecipientLayout];
    if (self.animatedRecipientsInAndOut) {
        recipientView.frame = [self _frameFoRecipientView:recipientView afterView:_recipientViews.lastObject];
        recipientView.alpha = 0.0;
        recipientView.transform = CGAffineTransformMakeScale(0.1, 0.1);
        
        // add this after getting the frame, otherwise it will base the frame on itself
        [_recipientViews addObject:recipientView];
        
        void(^animations)() = ^{
            recipientView.transform = CGAffineTransformIdentity;
            recipientView.alpha = 1.0;
            
            [self layoutIfNeeded];
        };
        
        if ([UIView respondsToSelector:@selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:)]) {
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.2 options:0 animations:animations completion:nil];
        } else {
            [UIView animateWithDuration:0.5 animations:animations];
        }
    } else {
        [_recipientViews addObject:recipientView];
        [self layoutIfNeeded];
    }
    
    
    if (_textField.editing) {
        [self _scrollToBottomAnimated:YES];
    } else {
        recipientView.alpha = 0.0;
    }
	
    _placeholderLabel.hidden = YES;
    
    [self _updateSummaryWithRecipient:recipient];
}


- (void)_configureSummaryRecipientLabel:(UILabel *)label forRecipient:(id<TURecipient>)recipient
{
    CGFloat labelWidth;
    CGSize availableSpace = CGSizeMake(CGFLOAT_MAX, [self _summaryContainerViewFrame].size.height);
    
    NSString *compoundRecipientTitle = nil;
    
    if ([_recipients indexOfObject:recipient] > 0)
    {
        compoundRecipientTitle = [NSString stringWithFormat:@", %@", recipient.recipientTitle];
    }
    else
    {
        compoundRecipientTitle = recipient.recipientTitle;
    }
    
    if (self.summaryTextAttributes)
    {
        label.attributedText = [[NSAttributedString alloc] initWithString:compoundRecipientTitle
                                                               attributes:self.summaryTextAttributes];
        
        labelWidth = [label.attributedText boundingRectWithSize:availableSpace
                                                        options:NSStringDrawingUsesLineFragmentOrigin
                                                        context:nil].size.width;
    }
    else
    {
        label.text = compoundRecipientTitle;
        
        NSDictionary *attributes = @{NSFontAttributeName : [UIFont systemFontOfSize:15.0]};
        
        labelWidth = [label.text boundingRectWithSize:availableSpace
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:attributes
                                              context:nil].size.width;
    }
    
    CGRect labelRect = label.frame;
    labelRect.size.width = labelWidth;
    labelRect.size.height = _summaryContainerView.bounds.size.height;
    label.frame = labelRect;
}


- (void)_setSummaryContainerViewMaskHidden:(BOOL)hidden
{
    if (hidden == NO && _summaryGradientMaskLayer == nil)
    {
        _summaryGradientMaskLayer = [CAGradientLayer layer];
        _summaryGradientMaskLayer.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor whiteColor].CGColor];
        _summaryGradientMaskLayer.frame = _summaryContainerView.bounds;
        _summaryGradientMaskLayer.startPoint = CGPointMake(0.0, 0.5);
        _summaryGradientMaskLayer.endPoint = CGPointMake(0.1, 0.5);
    }
    
    _summaryContainerView.layer.mask = (hidden ? nil : _summaryGradientMaskLayer);
}


- (void)_updateSummaryWithRecipient:(id<TURecipient>)recipient
{
    UILabel *lastRecipient = _summaryContainerView.subviews.lastObject;
    
    UILabel *newRecipientLabel = [[UILabel alloc] init];
    [_summaryContainerView addSubview:newRecipientLabel];
    
    [self _configureSummaryRecipientLabel:newRecipientLabel forRecipient:recipient];
    
    CGFloat leftPadding = 1.0;
    CGFloat summaryWidth = _summaryContainerView.bounds.size.width;
    CGFloat horizontalSpaceLeft = (lastRecipient == nil ? summaryWidth
                                                        : summaryWidth - CGRectGetMaxX(lastRecipient.frame));
    
    BOOL notEnoughSpaceToLayoutAllRecipientsOnOneRow =
        (horizontalSpaceLeft - (leftPadding + newRecipientLabel.bounds.size.width) <= 0.0);
    
    if (lastRecipient != nil && notEnoughSpaceToLayoutAllRecipientsOnOneRow)
    {
        [self _layoutSummaryRecipientsRightAligned];
        
        [self _setSummaryContainerViewMaskHidden:NO];
    }
    else
    {
        CGRect rect = newRecipientLabel.frame;
        rect.origin.x = leftPadding + (lastRecipient ? CGRectGetMaxX(lastRecipient.frame) : 0.0);
        rect.origin.y = 0.0;
        newRecipientLabel.frame = rect;
        
        [self _setSummaryContainerViewMaskHidden:YES];
    }
    
    // TODO: do not animate if the summary is not visible
    newRecipientLabel.alpha = 0.0;
    newRecipientLabel.transform = CGAffineTransformMakeScale(0.2, 0.2);
    
    [UIView animateWithDuration:0.4
                          delay:0.0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^() {
                         newRecipientLabel.alpha = 1.0;
                         newRecipientLabel.transform = CGAffineTransformIdentity;
                     } completion:^(BOOL finished) {
                         
                     }];
}


- (void)removeRecipient:(id<TURecipient>)recipient
{
    NSUInteger recipientIndex = [_recipients indexOfObject:recipient];
	NSIndexSet *changedIndex = [NSIndexSet indexSetWithIndex:recipientIndex];
	
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:changedIndex forKey:@"recipients"];
	[_recipients removeObjectsAtIndexes:changedIndex];
	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:changedIndex forKey:@"recipients"];
	
    UIView *recipientView = [_recipientViews objectAtIndex:changedIndex.firstIndex];
    [_recipientViews removeObject:recipientView];
    [self _setNeedsRecipientLayout];
    
    if (self.animatedRecipientsInAndOut) {
        void(^animations)() = ^{
            recipientView.transform = CGAffineTransformMakeScale(0.1, 0.1);
            recipientView.alpha = 0.0;
            
            [self layoutIfNeeded];
        };
        
        void (^completion)(BOOL finished) = ^(BOOL finished){
            [recipientView removeFromSuperview];
        };
        
        if ([UIView respondsToSelector:@selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:)]) {
            [UIView animateWithDuration:0.5 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.2 options:0 animations:animations completion:completion];
        } else {
            [UIView animateWithDuration:0.5 animations:animations completion:completion];
        }
    } else {
        [recipientView removeFromSuperview];
    }
	
    UILabel *firstSummaryLabel = _summaryContainerView.subviews.firstObject;
    UILabel *lastSummaryLabel = _summaryContainerView.subviews.lastObject;
    UILabel *removedSummaryLabel = _summaryContainerView.subviews[recipientIndex];
    
    if ([_summaryContainerView.subviews indexOfObject:removedSummaryLabel] == 0 &&
        [_summaryContainerView.subviews count] > 1)
    {
        UILabel *summaryLabelAfterTheRemovedOne = _summaryContainerView.subviews[1];
        
        [self _configureSummaryRecipientLabel:summaryLabelAfterTheRemovedOne forRecipient:_recipients[0]];
    }
    
    // TODO: do not animate if the summary is not visible
    void (^animation)() = ^()
    {
        removedSummaryLabel.alpha = 0.0;
        removedSummaryLabel.transform = CGAffineTransformMakeScale(0.1, 0.1);
        
        CGFloat leftPadding = 1.0;
        CGFloat minX = firstSummaryLabel.frame.origin.x;
        CGFloat maxX = CGRectGetMaxX(lastSummaryLabel.frame);
        CGFloat usedHorizontalSpace = fabs(minX) + maxX;
        
        if (usedHorizontalSpace - removedSummaryLabel.bounds.size.width - leftPadding <= _summaryContainerView.bounds.size.width)
        {
            UILabel *previousRecipientLabel = nil;
            
            for (NSInteger index = 0; index < [_summaryContainerView.subviews count]; index++)
            {
                if (index == recipientIndex)
                {
                    continue;
                }
                
                UILabel *currentRecipientLabel = _summaryContainerView.subviews[index];
                
                CGRect rect = currentRecipientLabel.frame;
                rect.origin.x = (previousRecipientLabel ? CGRectGetMaxX(previousRecipientLabel.frame) : 0.0) + leftPadding;
                currentRecipientLabel.frame = rect;
                
                previousRecipientLabel = currentRecipientLabel;
            }
            
            [self _setSummaryContainerViewMaskHidden:YES];
        }
        else
        {
            UILabel *previousRecipientLabel = nil;
            
            for (NSInteger index = [_summaryContainerView.subviews count] - 1; index >= 0; index--)
            {
                if (index == recipientIndex)
                {
                    continue;
                }
                
                UILabel *currentRecipientLabel = _summaryContainerView.subviews[index];
                
                CGRect rect = currentRecipientLabel.frame;
                rect.origin.x = (previousRecipientLabel ? previousRecipientLabel.frame.origin.x - leftPadding - rect.size.width
                                                        : _summaryContainerView.bounds.size.width - rect.size.width);
                currentRecipientLabel.frame = rect;
                
                previousRecipientLabel = currentRecipientLabel;
            }
            
            [self _setSummaryContainerViewMaskHidden:NO];
        }
        
        [removedSummaryLabel removeFromSuperview];
    };
    
    [UIView animateWithDuration:0.4
                          delay:0.0
         usingSpringWithDamping:1.0
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:animation
                     completion:^(BOOL finished) {
                         [removedSummaryLabel removeFromSuperview];
                         
                         if ([_recipients count] == 0)
                         {
                             _placeholderLabel.hidden = NO;
                         }
                     }];
}

- (void)setAutocapitalizationType:(UITextAutocapitalizationType)autocapitalizationType
{
	[_textField setAutocapitalizationType:autocapitalizationType];
}

- (UITextAutocapitalizationType)autocapitalizationType
{
	return [_textField autocapitalizationType];
}

- (void)setAutocorrectionType:(UITextAutocorrectionType)autocorrectionType
{
	[_textField setAutocorrectionType:autocorrectionType];
}

- (UITextAutocorrectionType)autocorrectionType
{
	return [_textField autocorrectionType];
}

- (void)setKeyboardType:(UIKeyboardType)keyboardType
{
	[_textField setKeyboardType:keyboardType];
}

- (UIKeyboardType)keyboardType
{
	return [_textField keyboardType];
}

- (void)setSpellCheckingType:(UITextSpellCheckingType)spellCheckingType
{
	[_textField setSpellCheckingType:spellCheckingType];
}

- (UITextSpellCheckingType)spellCheckingType
{
	return [_textField spellCheckingType];
}

- (void)setShowsAddButton:(BOOL)showsAddButton
{
    _showsAddButton = showsAddButton;
    
    if (_showsAddButton) {
        [self addSubview:_addButton];
    } else {
        [_addButton removeFromSuperview];
    }
    
    [self setNeedsLayout];
}

- (void)setShowsShadows:(BOOL)showsShadows
{
	_showsShadows = showsShadows;
    
	[self updateShadows];
}

- (void)setText:(NSString *)text
{
	if (text != nil) {
		[_textField setText:[TURecipientsPlaceholder stringByAppendingString:text]];
	} else {
		[_textField setText:TURecipientsPlaceholder];
	}
	
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBar:textDidChange:)]) {
		[self.recipientsBarDelegate recipientsBar:self textDidChange:self.text];
	}
}

- (NSString *)text
{
	return [[_textField text] stringByReplacingOccurrencesOfString:TURecipientsPlaceholder withString:@""];
}

- (void)setLabel:(NSString *)label
{
    _toLabel.attributedText = [[NSAttributedString alloc] initWithString:label ?: @"" attributes:self.labelTextAttributes];
}

- (NSString *)label
{
	return [_toLabel text];
}

- (void)setHeightConstraint:(NSLayoutConstraint *)heightConstraint
{
	if (_heightConstraint != heightConstraint) {
		[self removeConstraint:_heightConstraint];
		
		_heightConstraint = heightConstraint;
	}
}

- (void)setSearching:(BOOL)searching
{
	if (_searching != searching) {
		_searching = searching;
		
		[self setNeedsLayout];
		[self.superview layoutIfNeeded];
		
		[self _scrollToBottomAnimated:YES];
		
		if (_searching) {
			self.scrollEnabled = NO;
			_lineView.hidden = NO;
			_lineView.backgroundColor = [UIColor colorWithWhite:0.557 alpha:1.000];
		} else {
			_lineView.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.000];
		}
		
		[self updateShadows];
	}
}

- (void)setSearching:(BOOL)searching animated:(BOOL)animated
{
	if (animated) {
		[UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
			[self setSearching:searching];
		} completion:nil];
	} else {
		[self setSearching:searching];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"selectedTextRange"] && object == _textField) {
		//we use a special character at the start of the field that we don't want the user to select or move the insertion point in front of
		//see shouldChangeCharactersInRange for details
		NSInteger offset = [_textField offsetFromPosition:_textField.beginningOfDocument toPosition:_textField.selectedTextRange.start];
		
		if (offset < 1) {
			UITextPosition *newStart = [_textField positionFromPosition:_textField.beginningOfDocument offset:1];
			_textField.selectedTextRange = [_textField textRangeFromPosition:newStart toPosition:_textField.selectedTextRange.end];
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark - Visual Updates

- (void)_updateSummary
{
    if (_recipients.count > 0) {
        _placeholderLabel.hidden = YES;
        
        // TODO: should recreate all the summary
    } else {
        _placeholderLabel.hidden = NO;
        _placeholderLabel.textColor = [UIColor lightGrayColor];
        
        if (self.placeholderTextAttributes == nil) {
            _placeholderLabel.text = self.placeholder;
        } else {
            _placeholderLabel.attributedText =
                [[NSAttributedString alloc] initWithString:self.placeholder
                                                attributes:self.placeholderTextAttributes];
        }
    }
}


- (void)updateShadows
{
	if (_searching) {
		if (_showsShadows) {
			self.layer.shadowColor = [UIColor blackColor].CGColor;
			self.layer.shadowOffset = CGSizeMake(0.0, 0.0);
			self.layer.shadowOpacity = 0.5;
			self.layer.shadowRadius = 5.0;
			self.clipsToBounds = NO;
		}
	} else {
		if (_showsShadows) {
			self.layer.shadowOpacity = 0.0;
			self.layer.shadowRadius = 0.0;
			self.clipsToBounds = YES;
		}
	}
}


#pragma mark - Initialization

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[_textField removeObserver:self forKeyPath:@"selectedTextRange" context:TURecipientsSelectionContext];
}

- (void)_init
{
    _showsAddButton = YES;
	_showsShadows = YES;
    _animatedRecipientsInAndOut = YES;
    _recipientBackgroundImages = [NSMutableDictionary new];
    _recipientTitleTextAttributes = [NSMutableDictionary new];
    
    _recipientContentEdgeInsets = UIEdgeInsetsMake(0.0, 9.0, 0.0, 9.0);
    _recipientsLineHeight = TURecipientsLineHeight;
    _recipientsHorizontalMargin = 6.0;
    
    _bottomLineHeight = 1.0;
    
    self.contentSize = self.bounds.size;
    
	_recipients = [NSMutableArray array];
	_recipientViews = [NSMutableArray array];
	
	
	self.backgroundColor = [UIColor whiteColor];
	if (self.heightConstraint == nil) {
		_heightConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:0 multiplier:1.0 constant:_recipientsLineHeight + 1.0];
        _heightConstraint.priority = UILayoutPriorityDefaultHigh;
		[self addConstraint:_heightConstraint];
	}
	self.clipsToBounds = YES;
	
    if (_bottomLineHeight > 0.0)
    {
        _lineView = [[UIView alloc] init];
        _lineView.backgroundColor = [UIColor colorWithWhite:0.800 alpha:1.000];
        [self addSubview:_lineView];
    }
    
	_toLabel = [[UILabel alloc] init];
    self.label = NSLocalizedString(@"To: ", nil);
	[self addSubview:_toLabel];
	
	_addButton = [UIButton buttonWithType:UIButtonTypeContactAdd];
    _addButton.alpha = 0.0;
	[_addButton addTarget:self action:@selector(addContact:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:_addButton];
	
	_textField = [[UITextField alloc] init];
	_textField.text = TURecipientsPlaceholder;
    _textField.font = [UIFont systemFontOfSize:15.0];
    _textField.textColor = [UIColor blackColor];
	_textField.delegate = self;
	_textField.autocorrectionType = UITextAutocorrectionTypeNo;
	_textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_textField.spellCheckingType = UITextSpellCheckingTypeNo;
	_textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	[self addSubview:_textField];
	[_textField addObserver:self forKeyPath:@"selectedTextRange" options:0 context:TURecipientsSelectionContext];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textFieldDidChange:)
                                                 name:UITextFieldTextDidChangeNotification
                                               object:_textField];

    _summaryContainerView = [[UIView alloc] init];
    _summaryContainerView.clipsToBounds = YES;
    [self addSubview:_summaryContainerView];
    
	_placeholderLabel = [[UILabel alloc] init];
	_placeholderLabel.font = [UIFont systemFontOfSize:15.0];
	[self addSubview:_placeholderLabel];
	
	[self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(select:)]];
    
    
    
    [self _setNeedsRecipientLayout];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        if (CGRectEqualToRect(self.frame, CGRectZero)) {
            // often because of autolayout we will be initialized with a zero rect
            // we need to have a default size that we can layout against
            self.frame = CGRectMake(0.0, 0.0, 320.0, 44.0);
        }
        
        [self _init];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    if (CGRectEqualToRect(frame, CGRectZero)) {
        // often because of autolayout we will be initialized with a zero rect
        // we need to have a default size that we can layout against
        frame = CGRectMake(0.0, 0.0, 320.0, 44.0);
    }
    
    self = [super initWithFrame:frame];
    if (self != nil) {
		[self _init];
    }
	
    return self;
}


#pragma mark - Layout

- (void)_setNeedsRecipientLayout
{
    _needsRecipientLayout = YES;
    [self setNeedsLayout];
}

- (CGRect)_frameFoRecipientView:(UIView *)recipientView afterView:(UIView *)lastView
{
    CGRect recipientViewFrame;
    if (recipientView == _textField) {
        recipientViewFrame.size = CGSizeMake(100.0, self.recipientsLineHeight);
    } else {
        recipientViewFrame.size = recipientView.intrinsicContentSize;
    }
    
    if (lastView == _toLabel) {
        recipientViewFrame.origin.x = CGRectGetMaxX(lastView.frame);
    } else {
        recipientViewFrame.origin.x = CGRectGetMaxX(lastView.frame) + self.recipientsHorizontalMargin;
    }
    
    recipientViewFrame.origin.y = CGRectGetMidY(lastView.frame) - recipientViewFrame.size.height / 2.0;
    
    if (CGRectGetMaxX(recipientViewFrame) > self.bounds.size.width - self.recipientsHorizontalMargin) {
        recipientViewFrame.origin.x = 8.0;
        recipientViewFrame.origin.y += self.recipientsLineHeight - 8.0;
    }
    
    return recipientViewFrame;
}

- (void)layoutSubviews
{
	[super layoutSubviews];
    
    
    if (_needsRecipientLayout) {
        CGSize toSize = _toLabel.intrinsicContentSize;
        _toLabel.frame = CGRectMake(8.0,
                                    21.0 - toSize.height / 2,
                                    toSize.width, toSize.height);
        
        CGRect containerViewFrame = [self _summaryContainerViewFrame];
        _placeholderLabel.frame = containerViewFrame;
        _summaryContainerView.frame = containerViewFrame;
        
        CGRect addButtonFrame;
        addButtonFrame.size = _addButton.intrinsicContentSize;
        addButtonFrame.origin.x = self.bounds.size.width - addButtonFrame.size.width - 6.0;
        
        UIView *lastView = _toLabel;
        
        for (UIView *recipientView in [_recipientViews arrayByAddingObject:_textField]) {
            CGRect recipientViewFrame = [self _frameFoRecipientView:recipientView afterView:lastView];
            
            if (recipientView == _textField) {
                if (_addButton.superview == self) {
                    recipientViewFrame.size.width = addButtonFrame.origin.x - recipientViewFrame.origin.x;
                } else {
                    recipientViewFrame.size.width = self.bounds.size.width - recipientViewFrame.origin.x;
                }
            }
            
            recipientView.frame = recipientViewFrame;
            
            
            lastView = recipientView;
        }
        
        
        self.contentSize = CGSizeMake(self.frame.size.width,
                                      MAX(CGRectGetMaxY(lastView.frame), TURecipientsLineHeight) + 1);
        
        
        _needsRecipientLayout = NO;
        
        addButtonFrame.origin.y = self.contentSize.height - addButtonFrame.size.height / 2.0 - self.recipientsLineHeight / 2.0;
        _addButton.frame = addButtonFrame;
    }
    
    [_lineView.superview bringSubviewToFront:_lineView];
    if (self.searching) {
        _lineView.frame = CGRectMake(0.0, self.contentSize.height - self.bottomLineHeight,
                                     self.bounds.size.width, self.bottomLineHeight);
    } else {
        _lineView.frame = CGRectMake(0.0, self.contentOffset.y + self.bounds.size.height - self.bottomLineHeight,
                                     self.bounds.size.width, self.bottomLineHeight);
    }
    
    if (_textField.isFirstResponder && !self.searching) {
		self.heightConstraint.constant = self.contentSize.height;
	} else {
		self.heightConstraint.constant = self.recipientsLineHeight + 1.0;
	}
    
    if (_searching) {
		[self _scrollToBottomAnimated:NO];
	}
    
    
	if (_textField.isFirstResponder && self.contentSize.height > self.frame.size.height && !_searching) {
		self.scrollEnabled = YES;
	} else {
		self.scrollEnabled = NO;
	}
}

- (void)_frameChanged
{
	if (_recipients != nil && self.bounds.size.width != _lastKnownSize.width) {
		[self _setNeedsRecipientLayout];
	}
    
    if (_textField.isFirstResponder && self.contentSize.height > self.frame.size.height && !_searching) {
		self.scrollEnabled = YES;
	} else {
		self.scrollEnabled = NO;
	}
	
	if (_textField.isFirstResponder
        && _selectedRecipient == nil
		&& (self.bounds.size.width != _lastKnownSize.width || self.bounds.size.height != _lastKnownSize.height)) {
		[self _scrollToBottomAnimated:NO];
	}
	
	_lastKnownSize = self.bounds.size;
}

- (void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
	
	[self _frameChanged];
}

- (void)setFrame:(CGRect)frame
{
	[super setFrame:frame];
	
	[self _frameChanged];
}


- (CGRect)_summaryContainerViewFrame
{
    CGRect frame;
    frame.origin.x = CGRectGetMaxX(_toLabel.frame);
    frame.size.height = ceil([UIFont systemFontOfSize:15.0].lineHeight);
    frame.origin.y = 21.0 - frame.size.height / 2;
    frame.size.width = self.bounds.size.width - frame.origin.x - 12.0;
    
    return frame;
}


- (void)_layoutSummaryRecipientsRightAligned
{
    CGFloat leftPadding = 1.0;
    
    UILabel *lastRecipientLabel = nil;
    
    for (NSInteger index = [_summaryContainerView.subviews count] - 1; index >= 0; index--)
    {
        UILabel *currentRecipientLabel = _summaryContainerView.subviews[index];
        
        CGRect rect = currentRecipientLabel.frame;
        CGFloat currentRecipientWidth = rect.size.width;
        rect.origin.x = (lastRecipientLabel ? lastRecipientLabel.frame.origin.x
                                            : _summaryContainerView.bounds.size.width) -
                                              leftPadding -
                                              currentRecipientWidth;
        currentRecipientLabel.frame = rect;
        
        lastRecipientLabel = currentRecipientLabel;
    }
}


#pragma mark - Actions

- (IBAction)addContact:(id)sender
{
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBarAddButtonClicked:)]) {
		[self.recipientsBarDelegate recipientsBarAddButtonClicked:self];
	}
}

- (IBAction)select:(id)sender
{
	[self becomeFirstResponder];
	
    self.selectedRecipient = nil;
}

- (IBAction)selectRecipientButton:(UIButton *)sender
{
	NSUInteger recipientIndex = [_recipientViews indexOfObject:sender];
	
	if (recipientIndex != NSNotFound && [_recipients count] > recipientIndex) {
        self.selectedRecipient = [_recipients objectAtIndex:recipientIndex];
	}
}

- (void)selectRecipient:(id<TURecipient>)recipient
{
    self.selectedRecipient = recipient;
}

- (void)setSelectedRecipient:(id<TURecipient>)recipient
{
	BOOL should = YES;
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBar:shouldSelectRecipient:)]) {
		should = [self.recipientsBarDelegate recipientsBar:self shouldSelectRecipient:recipient];
	}
	
	if (should) {
		if (_selectedRecipient != recipient) {
			_selectedRecipient = recipient;
			
			[self _updateRecipientTextField];
			
			if (_selectedRecipient != nil) {
				[_textField becomeFirstResponder];
			}
		}
		
		for (UIButton *recipientView in _recipientViews) {
			recipientView.selected = NO;
		}
		
		NSUInteger recipientIndex = [_recipients indexOfObject:recipient];
		
		if (recipientIndex != NSNotFound && [_recipientViews count] > recipientIndex) {
			UIButton *recipientView = [_recipientViews objectAtIndex:recipientIndex];
			recipientView.selected = YES;
		}
		
		
		if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBar:didSelectRecipient:)]) {
			[self.recipientsBarDelegate recipientsBar:self didSelectRecipient:recipient];
		}
	}
}

- (void)_updateRecipientTextField
{
	_textField.hidden = _selectedRecipient != nil || ![_textField isFirstResponder];
}

- (void)_scrollToBottomAnimated:(BOOL)animated
{
    [self setContentOffset:CGPointMake(0.0, self.contentSize.height - self.bounds.size.height) animated:animated];
}


#pragma mark - FirstResponder

- (BOOL)canBecomeFirstResponder
{
	return [_textField canBecomeFirstResponder];
}

- (BOOL)becomeFirstResponder
{
	return [_textField becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
	return [_textField resignFirstResponder];
}


#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
	//we use a zero width space to detect the backspace
	if ([[_textField.text substringWithRange:range] isEqual:TURecipientsPlaceholder]) {
		//select the last recipient
		if (_selectedRecipient == nil) {
			if (self.text.length == 0) {
                self.selectedRecipient = _recipients.lastObject;
			}
		} else {
			[self removeRecipient:_selectedRecipient];
            self.selectedRecipient = nil;
		}
		
		return NO;
	} else if (_selectedRecipient != nil) {
		//replace the selected recipient
		[self removeRecipient:_selectedRecipient];
        self.selectedRecipient = nil;
	}
	
	
	
	//adjust to protect our placeholder character
	if (range.location < 1) {
		range.location++;
		
		if (range.length > 0) {
			range.length--;
		}
	}
	
	BOOL delegateResponse = YES;
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBar:shouldChangeTextInRange:replacementText:)]) {
		delegateResponse = [self.recipientsBarDelegate recipientsBar:self shouldChangeTextInRange:range replacementText:string];
	}

    return delegateResponse;
}

- (void)_manuallyChangeTextField:(UITextField *)textField inRange:(NSRange)range replacementString:(NSString *)string
{
	//we save the offset from the end of the document and reset the selection to be a caret there
	NSInteger offset = [_textField offsetFromPosition:_textField.selectedTextRange.end toPosition:_textField.endOfDocument];
	
	textField.text = [textField.text stringByReplacingCharactersInRange:range withString:string];
	
	UITextPosition *newEnd = [_textField positionFromPosition:_textField.endOfDocument inDirection:UITextLayoutDirectionLeft offset:offset];
	_textField.selectedTextRange = [_textField textRangeFromPosition:newEnd toPosition:newEnd];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBarReturnButtonClicked:)]) {
		[self.recipientsBarDelegate recipientsBarReturnButtonClicked:self];
	}
	
	return NO;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	BOOL should = YES;
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBarShouldBeginEditing:)]) {
		should = [self.recipientsBarDelegate recipientsBarShouldBeginEditing:self];
	}
	
	return should;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField;
{
    [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        for (UIView *recipientView in _recipientViews) {
            recipientView.alpha = 1.0;
        }
        _textField.alpha = 1.0;
        _addButton.alpha = 1.0;
        
        _placeholderLabel.alpha = 0.0;
        _summaryContainerView.alpha = 0.0;
        
        
        [self setNeedsLayout];
        [self.superview layoutIfNeeded];
        
        [self _scrollToBottomAnimated:YES];
    } completion:^(BOOL finished) {
        if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBarTextDidBeginEditing:)]) {
            [self.recipientsBarDelegate recipientsBarTextDidBeginEditing:self];
        }
    }];
}

- (void)textFieldDidChange:(NSNotification *)notification
{
    if ([notification.object isEqual:self.textField] &&
        [self.recipientsBarDelegate respondsToSelector:@selector(recipientsBar:textDidChange:)]) {
        [self.recipientsBarDelegate recipientsBar:self textDidChange:self.text];
    }
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	BOOL should = YES;
	if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBarShouldEndEditing:)]) {
		should = [self.recipientsBarDelegate recipientsBarShouldEndEditing:self];
	}
	
	if (should) {
        // we want the animation to execute after the text field has resigned first responder
        
		dispatch_async(dispatch_get_main_queue(), ^{
			[UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
				self.scrollEnabled = NO;
				
				for (UIView *recipientView in _recipientViews) {
					recipientView.alpha = 0.0;
				}
				_textField.alpha = 0.0;
				_addButton.alpha = 0.0;
				
                _placeholderLabel.alpha = 1.0;
                _summaryContainerView.alpha = 1.0;
				
				[self setNeedsLayout];
				[self.superview layoutIfNeeded];
				
                [self setContentOffset:CGPointMake(0.0, 0.0) animated:YES];
			} completion:^(BOOL finished) {
				if ([self.recipientsBarDelegate respondsToSelector:@selector(recipientsBarTextDidEndEditing:)]) {
					[self.recipientsBarDelegate recipientsBarTextDidEndEditing:self];
				}
			}];
		});
	}
	
	return should;
}

- (void)setContentOffset:(CGPoint)contentOffset
{
    [super setContentOffset:contentOffset];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
    [super setContentOffset:contentOffset animated:animated];
}


#pragma mark - UIAppearance

- (void)setRecipientBackgroundImage:(UIImage *)backgroundImage forState:(UIControlState)state UI_APPEARANCE_SELECTOR
{
    if (backgroundImage == nil) {
        [_recipientBackgroundImages removeObjectForKey:@(state)];
    } else {
        _recipientBackgroundImages[@(state)] = backgroundImage;
    }
    
    backgroundImage = [self recipientBackgroundImageForState:state];
    
    for (UIButton *button in _recipientViews) {
        [button setBackgroundImage:backgroundImage forState:state];
    }
}

- (UIImage *)recipientBackgroundImageForState:(UIControlState)state UI_APPEARANCE_SELECTOR
{
    UIImage *backgroundImage = _recipientBackgroundImages[@(state)];
    
    if (backgroundImage == nil) {
        if (state == UIControlStateNormal) {
            backgroundImage = [[UIImage imageNamed:@"recipient.png"] stretchableImageWithLeftCapWidth:14 topCapHeight:0];
        } else if (state == UIControlStateHighlighted) {
            backgroundImage = [[UIImage imageNamed:@"recipient-selected.png"] stretchableImageWithLeftCapWidth:14 topCapHeight:0];
        } else if (state == UIControlStateSelected) {
            backgroundImage = [[UIImage imageNamed:@"recipient-selected.png"] stretchableImageWithLeftCapWidth:14 topCapHeight:0];
        }
    }
    
    return backgroundImage;
}

- (void)setRecipientContentEdgeInsets:(UIEdgeInsets)recipientContentEdgeInsets
{
    _recipientContentEdgeInsets = recipientContentEdgeInsets;
    
    for (UIButton *button in _recipientViews) {
        button.contentEdgeInsets = _recipientContentEdgeInsets;
    }
}

- (void)setRecipientTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state
{
    if (attributes == nil) {
        [_recipientTitleTextAttributes removeObjectForKey:@(state)];
    } else {
        _recipientTitleTextAttributes[@(state)] = attributes.copy;
    }
    
    attributes = [self recipientTitleTextAttributesForState:state];
    
    for (UIButton *button in _recipientViews) {
        NSString *text = [button titleForState:state] ?: [button attributedTitleForState:state].string ?: @"";
        NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:attributes];
        [button setAttributedTitle:attributedText forState:state];
    }
}

- (NSDictionary *)recipientTitleTextAttributesForState:(UIControlState)state
{
    NSDictionary *attributes = _recipientTitleTextAttributes[@(state)];
    
    if (attributes == nil) {
        if (state == UIControlStateNormal) {
            attributes = @{
                           NSFontAttributeName: [UIFont systemFontOfSize:15.0],
                           NSForegroundColorAttributeName: [UIColor blackColor],
                           };
        } else if (state == UIControlStateHighlighted) {
            attributes = @{
                           NSFontAttributeName: [UIFont systemFontOfSize:15.0],
                           NSForegroundColorAttributeName: [UIColor whiteColor],
                           };
        } else if (state == UIControlStateSelected) {
            attributes = @{
                           NSFontAttributeName: [UIFont systemFontOfSize:15.0],
                           NSForegroundColorAttributeName: [UIColor whiteColor],
                           };
        }
    }
    
    return attributes;
}

- (void)setSummaryTextAttributes:(NSDictionary *)attributes
{
    _summaryTextAttributes = [attributes copy];
    
    [self _updateSummary];
}

- (void)setSearchFieldTextAttributes:(NSDictionary *)attributes
{
    _searchFieldTextAttributes = [attributes copy];
    
    if (_searchFieldTextAttributes[NSFontAttributeName] != nil) {
        _textField.font = _searchFieldTextAttributes[NSFontAttributeName];
    } else {
        _textField.font = [UIFont systemFontOfSize:16.0];
    }
    
    if (_searchFieldTextAttributes[NSForegroundColorAttributeName] != nil) {
        _textField.textColor = _searchFieldTextAttributes[NSForegroundColorAttributeName];
    } else {
        _textField.textColor = [UIColor blackColor];
    }
}

- (void)setPlaceholderTextAttributes:(NSDictionary *)attributes
{
    _placeholderTextAttributes = [attributes copy];
    
    [self _updateSummary];
}

- (void)setLabelTextAttributes:(NSDictionary *)attributes
{
    _labelTextAttributes = attributes;
    
    NSString *text = _toLabel.text;
    NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:_labelTextAttributes];
    _toLabel.attributedText = attributedText;
}

- (NSDictionary *)labelTextAttributes
{
    NSDictionary *labelTextAttributes = _labelTextAttributes;
    
    if (labelTextAttributes == nil) {
        labelTextAttributes = @{
                                NSForegroundColorAttributeName: [UIColor colorWithWhite:0.498 alpha:1.000],
                                NSFontAttributeName: [UIFont systemFontOfSize:17.0],
                                };
    }
    
    return labelTextAttributes;
}

@end
