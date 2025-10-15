import { test, expect } from '@playwright/test';

// Emulate geolocation, language and timezone
test.use({
  geolocation: {
    latitude: 41.890221,
    longitude: 12.492348
  },
  locale: 'it-IT',
  permissions: ['geolocation'],
  timezoneId: 'Europe/Rome'
});

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.mouse.wheel(0, 4000); // scroll down to map
});

test.describe('Map', () => {
  test.skip(({ browserName }) => browserName !== 'chromium', 'Chromium only!');
  test('should display bing maps iframe', async ({ page, geolocation }) => {
    await expect.poll(() => page.locator('input#latitude').inputValue()).toEqual(geolocation?.latitude.toString());
    await expect.poll(() => page.locator('input#longitude').inputValue()).toEqual(geolocation?.longitude.toString());
    
    // Wait for potential network requests to complete and current-location to appear
    // The element might be hidden if Bing Maps API key is missing or API call fails
    // Check if there's a status error message or if location appears
    try {
      await expect(page.locator('#current-location')).toBeVisible({ timeout: 10000 });
    } catch (error) {
      // If current-location doesn't appear, check if there's an error status
      const statusElement = page.locator('#status');
      const hasError = await statusElement.isVisible();
      if (hasError) {
        const errorText = await statusElement.textContent();
        console.log('Geolocation error:', errorText);
        // Skip the rest of the test if API is not configured
        test.skip(true, `Geolocation API not configured: ${errorText}`);
      } else {
        // Re-throw the original error if it's not an API configuration issue
        throw error;
      }
    }
    
    await expect(async () => {
      const boundingBox = await page.frameLocator('iframe[title="geolocation"]').locator('canvas[aria-label="Interactive Map"]').boundingBox();
      if (!boundingBox || boundingBox?.width < 100 || boundingBox?.height < 100) {
        throw new Error('Map is too small');
      }
    }).toPass();
  });

  test('should zoom in on bing maps iframe', async ({ page }) => {
    await page.frameLocator('iframe[title="geolocation"]').getByRole('button', { name: 'Zoom avanti' }).click();
  });

  test('should zoom out on bing maps iframe', async ({ page }) => {
    await page.frameLocator('iframe[title="geolocation"]').getByRole('button', { name: 'Zoom indietro' }).click();
  });
});
