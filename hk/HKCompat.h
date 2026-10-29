/*
 * HKCompat.h -- what the HighlighterKit sources (written for GNUstep) need that OPENSTEP 4.2 / the
 * modern SDK do not provide.  Included first by every HK source file.
 */
#ifndef HKCOMPAT_H
#define HKCOMPAT_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#define _(s) s                                      /* GNUstep's localisation macro */

#ifndef ASSIGN
#define ASSIGN(var, val) do { id hk_tmp_ = [(val) retain]; [(var) release]; (var) = hk_tmp_; } while (0)
#endif
#ifndef ASSIGNCOPY
#define ASSIGNCOPY(var, val) do { id hk_tmp_ = [(val) copy]; [(var) release]; (var) = hk_tmp_; } while (0)
#endif
#ifndef TEST_RELEASE
#define TEST_RELEASE(var) do { if ((var) != nil) [(var) release]; } while (0)
#endif

/* A marker attribute value: NSNull is not in OPENSTEP 4.2's Foundation. */
#define HK_MARK_VALUE() [NSNumber numberWithInt:1]

#endif
