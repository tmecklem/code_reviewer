# Code Review Preferences Analysis

**Reviewer:** tmecklem
**Analysis Date:** 2026-02-03T16:28:32-05:00
**Total Comments Analyzed:** 814

## Testing Preferences

### test_organization

- **Elixir and devcontainer upgrade**
  ```
  This and the update project function were changed in part from the changes to Decimal and the switch to the Jason library from Poison. This should be tested manually  
  ```
  [Link](https://github.com/ParkerDewey/parker-dewey/pull/1381)

- **Design/pie form**
  ```
  Good work overall! 

Need some specs asserting that twilio gets called at the right times and for some of the error cases. In order to do that:

```
create a configuration object using ActiveSupport::Configurable that can be set with the twilio configuration information. Put the configuration in the config/initializers/twilio.rb file and have it read the environment variables there to set the config. Remove references to the ENV for twilio everywhere else and use that configuration instead. Create specs testing the twilio jobs nd ensuring that the various error cases are handled appropriately. Extract the job code to services if needed for easier testing.
```
  ```
  [Link](https://github.com/busken-bakery/busken_fundraiser/pull/161)

- **Coupon code rules**
  ```
  I don't think we should necessarily do it this way. It's not wrong, but I think I'd prefer a different way in a followup PR:
Rather than marking a certificatedesign as used, we want to add a belongs_to relationship on Reservations so that a reservation belongs to a CertificateDesign. CertificateDesign should have a with_reservations scope added that is all CertificateDesigns with at least one reservation. Additionally, an instance method of #used? should use the same logic to return whether a certificatedesign has been referenced by a Reservation. coupon_code_editable? should be updated to use this new approach for whether CertificateDesign has at least one Reservation. Update the first_used logic to find the oldest reservation created_at that references the certificatedesign. Continue to store the coupon_code on the Reservation as well. Remove `certificate_design` method on the Reservation, since the belongs_to will handle that. Write tests for these first that fail, and then pass them. Run bin/standardrb --fix and bin/erb_lint app -a
  ```
  [Link](https://github.com/busken-bakery/busken_fundraiser/pull/119)

- **Setup the home page form, add admin form control, and clean up nav for givethanks**
  ```
  This should be in a before. It detracts from the tests communication of intent in the it block.
  ```
  [Link](https://github.com/busken-bakery/busken_fundraiser/pull/88)

- **Setup the home page form, add admin form control, and clean up nav for givethanks**
  ```
  This should be in a before. It detracts from the test's communication of intent
  ```
  [Link](https://github.com/busken-bakery/busken_fundraiser/pull/88)

### mocking_stubbing_preference

- **Add HEB price extraction**
  ```
  It kind of looks like we're testing the mock later on
  ```
  [Link](https://github.com/gather-data-platform/pricing_scraper/pull/43)

- **Bey 362 - Recipes Module**
  ```
  It's a little odd to see conditional mocking in a before. It looks like form is always defined, so maybe this is Claude being Claude?
  ```
  [Link](https://github.com/todd-inc/todd/pull/1134)

- **Fa31304 Receive products directly to job**
  ```
  I don't like all the mocking of this data at all. It should just use real data since that's fast enough and a better test of the actual behavior of the system. But this is better than nothing for something that is "free" to generate.
  ```
  [Link](https://github.com/EBeam/Presto/pull/11)

- **BEY-400 / BEY-402 / BEY-404 / BEY-415 / BEY-416 - Advisor AI Assistant Foundation**
  ```
  I prefer to just use the real thing for this kind of test. Claude likes to mock. A lot. Just noting this mock here in case you also prefer to test against real data and got Clauded.
  ```
  [Link](https://github.com/todd-inc/todd/pull/1039)

- **BEY-400 / BEY-402 / BEY-404 / BEY-415 / BEY-416 - Advisor AI Assistant Foundation**
  ```
  More mocking here. Which is cool is that's what you intended, just noting because Claude likes to mock me with so many mocks for everything.
  ```
  [Link](https://github.com/todd-inc/todd/pull/1039)

### test_coverage

- **Fa31304 Receive products directly to job**
  ```
  I ran code coverage on the project and noted that this controller was missing coverage so I had Claude generate tests. It generated this confusingly named method and I thought it was wrong, but it looks like the ViewBag property name is the confusing thing. I added a note further down for it. 

Specifically, I would expect hasNoReceiptLineItems to be false (or the variable name to be changed to remove the `No` in the case where there _are_ ReceiptLineItems.
  ```
  [Link](https://github.com/EBeam/Presto/pull/11)

- **[BEY-76] Normalize person**
  ```
  I put this in a class separately so I could have good test coverage for it.
  ```
  [Link](https://github.com/todd-inc/todd/pull/523)

- **Feature/sending days open to hubspot each day**
  ```
  Good test case! Sometimes APIs will error if you send an empty list for a batch, so I appreciate your diligence in thinking about additional cases here.
  ```
  [Link](https://github.com/ParkerDewey/parker-dewey/pull/866)

### push_tests_down_hierarchy

- **Fa31304 Receive products directly to job**
  ```
  I pushed a change that introduces `hasNoWorkInProgress = !model.receiptLineItems.Any(x => x.WorkOrderLineItems.Any());`

If I understand correctly, that's the spirit of the intended change. I also added tests to that effect.
  ```
  [Link](https://github.com/EBeam/Presto/pull/11)

- **Bey 166 trustee asset assignment**
  ```
  I have to constantly tell Cursor to push the system tests lower. There must be a huge body of unfortunate and slow system specs out there, because it's the thing I fight about the most with Cursor by far. I think we need some cursor rules about it. We're already slowing the spec runs down quite a bit from non-happy path system specs that could easily be request or model specs.
  ```
  [Link](https://github.com/todd-inc/todd/pull/697)

## Code Organization Preferences

### modules_concerns

- **Devcontainer tweaks**
  ```
  I'm okay with this, and it need reconciliation with the post start script that sets processors statically: `bin/parallel_setup`. I want non-linux environments to still work without the dev container, so if the change is made to put this here it needs to be confirmed to work on bare macOS with the Etc module lookups. I don't care about native Windows support though, since WSL is the way to go there.
  ```

- **Add Plan Analysis feature for advisors**
  ```
  I'm not a super big fan of these kinds of direct broadcasts from the model. I know it's supposed to be the hotwire "way", but my brain melts with the whole conflation of concerns and tight coupling of model to its representation. I much prefer the active support Notification as a pub sub mechanism and then having something listen for an AR callback-initiated event. I may refactor this later into that, but it's really interesting for now to see an LLM follow the hotwire TurboStreamsChannel happy path for real time.
  ```

- **Machine booking upgrades**
  ```
  Good work. Just the magic numbers feedback needs to be addressed for now.

A few deeper concerns I have are around the controller and playwright tests and the amount of JS that's just there because we're in a modal now, but for now those can simmer for a bit.
  ```

- **Wire Military Service module to backend: persistence, routes, schema; run CI**
  ```
  Idiomatically, this should be plural, but I understand for how we're doing the modules that singular might make sense and be acceptable.
  ```

- **Bey 362 - Recipes Module**
  ```
  Also having recipe hardcoded here instead of interpolating the `nested_model` attribute of the screen seems like a missed opportunity to use that field to make lookup more dynamic. It's fine for a module that only has a single nested_model type, but it feels like it's missing the spirit of the nested_model idea.
  ```

### modules_concerns, separation_concerns

- **Add Plan Analysis feature for advisors**
  ```
  There's a lot going on in this PR! I think it does well to separate concerns and loosely couple the various components. I didn't see anything obvious that raises any concerns in data handling, so it's a go from my perspective.
  ```

- **Calendar updates**
  ```
  this is a hack. We need to separate the shipping link out of the inline list of machine ids. We'll deal with the lack of referential integrity for the machineIds separately if it becomes a big enough concern.
  ```

- **Post a new Project/Internship**
  ```
  Refactor opportunity

Business logic like this belongs somewhere other than the UI code layer. Either in an existing context function, perhaps in a schema module, or in a separate new module dedicated to it. It's kind of hidden here.
  ```

- **Coordinates**
  ```
  Let's revisit this and refactor it into a separate module that checks for recency on the last geocode to avoid accidentally refreshing all of the geocoded addresses needlessly.
  ```

### service_objects

- **Pie form feedback**
  ```
  Yes, this is great! Add a ton of confidence to the service working correctly on our side when configured correctly.
  ```

- **Design/pie form**
  ```
  Good work overall! 

Need some specs asserting that twilio gets called at the right times and for some of the error cases. In order to do that:

```
create a configuration object using ActiveSupport::Configurable that can be set with the twilio configuration information. Put the configuration in the config/initializers/twilio.rb file and have it read the environment variables there to set the config. Remove references to the ENV for twilio everywhere else and use that configuration instead. Create specs testing the twilio jobs nd ensuring that the various error cases are handled appropriately. Extract the job code to services if needed for easier testing.
```
  ```

- **[BEY-206] [BEY-207] Add ProcessWisefillDocumentJob for WiseFill Service Integration**
  ```
  Goal of the fake is to have as close to a zero config dev environment that's still realistic. For most cases, this is probably a sane default for development, unless you're testing the actual wisefill service.
  ```

- **[BEY-110] Migrate Google Chat notifications to Slack**
  ```
  It looks like the service handles rescuing and logging the error. This would be a confusing message to see in the log after one with more detail
  ```

- **[BEY-110] Migrate Google Chat notifications to Slack**
  ```
  It says in the Gemfile that the google auth is still needed for other services, but it removes the application credentials configuration here, and for some reason it's looking at the github actions credentials.
  ```

### separation_concerns

- **Calendar updates**
  ```
  yeah this is hacky. We should make this a separate join table before too long.
  ```

- **Calendar updates**
  ```
  The changes in this and in the devcontainer.json should be in a separate PR.
  ```

- **Add fully received button and report**
  ```
  This seems weird. Is it a good practice to base64 encode a spreadsheet vs a separate controller download?
  ```

- **BEY-345 separate sign in page**
  ```
  This is kind of a clunky way to handle this process. It makes me think we should combine advisors into users at some point, because of this kind of conditional logic and how pundit is expecting a user. We decided on separate, but it's worth revisiting that soon.
  ```

- **Katibest/bey 323 client list**
  ```
  @joelturnbull I'm not really sure I fully understand the distinction between the app/helpers/components shadcn generators and the app/components/* viewcomponents, but I suspect we'll want to do some work here to convert these over there if I understand your vision correctly. I'd propose we do that in followup work + lookbook rather than in this branch. (We're in a time crunch, and that seems useful as separate work anyway)
  ```

### extract_methods

- **[BEY-205] - Prevent other actions while document is processing**
  ```
  I don't have any major feedback on it. It's a big hammer, but that's essentially what we're trying to accomplish with it.

Two potential suggestions:
* Make an AuthenticatedController or something similar that all of the normally authenticated routes inherit from, so that we don't have to have as many exclusions. In some ways the current approach feels a little like an open-closed principle violation where we're setting behavior and then overriding it in subclasses, so my spidey-sense went off a little in that direction.
* Extract the direct_to_document_processing into a class that's a little more descriptive, like BlockingActionChecker or something. It's obvious why we're doing this since we're in the middle of wisefill, but I think if I came back to this in 6 months I'd be like, wait why is this method here again? It might be premature for that kind of a refactor, but you could argue for it as a single responsibility thing too. 

Feel free to ignore either of these in the interest of time or disagreement or "I just don't want to, Tim".
  ```

### service_objects, modules_concerns

- **Will Document Generation**
  ```
  this is actually a little less gross than how formatting calculations usually go. It's not ideal, but we're all on the same page I think. Improving this probably looks like using a native PDF generator or third party service, and this is good enough for now as far as I'm concerned.
  ```

- **Update alert messages for invalid requests in passwordless controller**
  ```
  I think there's a security concern with how we have passwordless implemented. Currently you get a different experience if you try to sign in using an email that isn't in the system vs one that is (it potentially leaks who has signed up for the service if you know their email address). I'd suggest that we should deliver the same page that says an email has been sent either way, and if you try to use an email not in the system, it directs you to the sign up page in the email instead of giving you a token. OWASP reference: https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html#authentication-responses
  ```

## Code Quality Patterns

### magic_values

- these magic numbers aren't great.

```
Either refactor the magic bookingType numbers to a helper method, or define them somewhere instead of using them as integer strings in the view.
```

- Good work. Just the magic numbers feedback needs to be addressed for now.

A few deeper concerns I have are around the controller and playwright tests and the amount of JS that's just there because we're in a modal now, but for now those can simmer for a bit.

- I have to constantly tell Cursor to push the system tests lower. There must be a huge body of unfortunate and slow system specs out there, because it's the thing I fight about the most with Cursor by far. I think we need some cursor rules about it. We're already slowing the spec runs down quite a bit from non-happy path system specs that could easily be request or model specs.

### naming_conventions

- Good work overall! 

Need some specs asserting that twilio gets called at the right times and for some of the error cases. In order to do that:

```
create a configuration object using ActiveSupport::Configurable that can be set with the twilio configuration information. Put the configuration in the config/initializers/twilio.rb file and have it read the environment variables there to set the config. Remove references to the ENV for twilio everywhere else and use that configuration instead. Create specs testing the twilio jobs nd ensuring that the various error cases are handled appropriately. Extract the job code to services if needed for easier testing.
```

- I ran code coverage on the project and noted that this controller was missing coverage so I had Claude generate tests. It generated this confusingly named method and I thought it was wrong, but it looks like the ViewBag property name is the confusing thing. I added a note further down for it. 

Specifically, I would expect hasNoReceiptLineItems to be false (or the variable name to be changed to remove the `No` in the case where there _are_ ReceiptLineItems.

- Would it be difficult to set up an environment variable or special bucket name that would return canned responses instead of talking to google every time? I was going to suggest turning the webmock in the Rails app into a small Rack app "fake", but since we own the document processor service we could just make this code amenable to testing/dev environments without hitting google.

It would be one less integration point for people to have to know/set up locally to get running. I don't have a strong opinion about it, but my default is to minimize the number of external keys and services needed for a new dev to the project to get up and running.

### nil_handling

- this is to work around the validation that allows_nil but doesn't consider blank values

- oof, lol. This makes me think more that we should move the owned by and other joint ownership fields to the Asset model and allow it to be nil for types that don't currently support joint ownership. Not a request for change, just thinking in terms of followup and cleaning up some of the verbosity here.

- present is true for false, had to change it to a nil check here and a few other places further along this chain.

### naming_conventions, magic_values

- Magic list... Maybe extract to an attribute with a good name. "@project_stages" or similar

- Module attributes are evaluated at compile-time (see http://elixir-br.github.io/getting-started/module-attributes.html#as-constants). This should be in a defp or somewhere else that will be dynamically calculated each time it is called.

### edge_cases

- Just an observation, not a recommendation for a change:

Matching on {:ok, project} here introduces a new way that the app could crash (the caller doesn't seem to assert anything about the behavior of the function). I think this is okay and also worth monitoring the crash logs for a while to ensure that we don't see a rise in user-facing errors. Reopening a project is already an edge case, so I think this is fine.

## Top 20 Common Phrases

- (9x) this looks good to me
- (7x) looks good overall
- (6x) this looks good
- (3x) recipientable
- (3x) looks good
- (2x) same as above, since our name is two separate words
- (2x) looks good to me
- (2x) this is great
- (2x) interesting
- (2x) did you mean to leave these logging statements in here
- (2x) good work overall
- (2x) this should be in a before
- (2x) this looks good overall
- (2x) i've come back and reviewed this after some time away
- (2x) i have reviewed this code
- (2x) looks great
- (2x) this looks great
- (2x) i like this
- (2x) looks great overall
- (2x) elsif recipientable

## Tone Characteristics

- **directive**: 168 instances
- **positive**: 118 instances
- **questioning**: 87 instances
- **suggestive**: 64 instances
- **cautionary**: 12 instances
